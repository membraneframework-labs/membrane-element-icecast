defmodule Membrane.Element.Icecast.Sink do
  use Membrane.Element.Base.Sink
  use Membrane.Mixins.Log, tags: :membrane_element_icecast
  alias Membrane.Time
  alias __MODULE__.Options
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.MPEG, as: Caps

  @moduledoc false

  def_known_sink_pads %{
    :sink => {:always, {:pull, demand_in: :buffers}, :any}
  }


  # Private API

  @doc false
  def handle_init(%Options{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout, frame_duration: frame_duration}) do
    {:ok, %{
      sock: nil,
      host: host,
      port: port,
      mount: mount,
      password: password,
      connect_timeout: connect_timeout,
      request_timeout: request_timeout,
      frame_duration: frame_duration,
      demanded_buffers: 1,
      first_tick: nil,
      tick_offset: 0.0,
      written_time: Time.monotonic_time,
      written: false,
    }}
  end


  @doc false
  def handle_play(%{host: host, port: port, connect_timeout: connect_timeout} = state) do
    case :gen_tcp.connect(to_charlist(host), port, [mode: :binary, packet: :line, active: false, keepalive: true], connect_timeout) do
      {:ok, sock} ->
        do_request(state, sock)

      {:error, reason} ->
        warn("Failed to connect to #{host}:#{port}: #{inspect(reason)}")
        {{:error, {:connect, reason}}, %{state | sock: nil}}
    end
  end

  defp do_request(%{host: host, mount: mount, password: password, request_timeout: request_timeout} = state, sock) do
    with credentials <- "source:#{password}" |> Base.encode64,
         {:request, :ok} <- {:request, :gen_tcp.send(sock, "SOURCE #{mount} HTTP/1.0\r\nAuthorization: Basic #{credentials}\r\nHost: #{host}\r\nUser-Agent: RadioKit Osmosis\r\nContent-Type: audio/mpeg\r\n\r\n")},
         {:response, {:ok, "HTTP/1.0 200 OK\r\n"}} <- {:response, :gen_tcp.recv(sock, 0, request_timeout)}
    do
      debug("Got OK response")
      send self(), :tick
      first_tick = Time.monotonic_time()
      {:ok, %{state | sock: sock, first_tick: first_tick}}
    else
      {:request, {:error, reason}} ->
        warn("Failed to send request: #{inspect(reason)}")
        :ok = :gen_tcp.close(sock)
        {{:error, {:request, reason}}, %{state | sock: nil}}

      {:response, {:ok, response}} ->
        warn("Got unexpected response: #{inspect(response)}")
        :ok = :gen_tcp.close(sock)
        {{:error, {:response, {:unexpected, response}}}, %{state | sock: nil}}

      {:response, {:error, reason}} ->
        warn("Failed to receive response: #{inspect(reason)}")
        :ok = :gen_tcp.close(sock)
        {{:error, {:response, reason}}, %{state | sock: nil}}
    end
  end

  @doc false
  def handle_caps(:sink, %Caps{sample_rate: sample_rate, version: version, layer: layer}, _params, state) do
    samples = Caps.samples_per_frame(version, layer)
    frame_duration = (1 |> Time.second |> Time.to_nanoseconds) * samples / sample_rate
    debug("New frame duration #{frame_duration}")
    {:ok, %{state | frame_duration: frame_duration}}
  end

  @doc """
  Function that is responsible for synchronization of streaming

  There are 3 important values kept in state:
  * first_tick - integer, monotonic_time in ns
  * tick_offset - float, in ns
  * frame_duration - float, in ns

  On each tick, this function adds frame_duration to current offset and stores new value in state
  To determine time in ms for `send_after` rounded offset is added to first_tick
  """
  def handle_other(:tick, state) do
    %{first_tick: first_tick, tick_offset: tick_offset,
      frame_duration: frame_duration, demanded_buffers: demanded_buffers,
      written: written} = state
    new_offset = tick_offset + frame_duration * demanded_buffers
    next_tick = first_tick + round(new_offset)
    _timer_ref = Process.send_after(self(), :tick, Time.to_milliseconds(next_tick), abs: true)
    state = %{state | tick_offset: new_offset}
    with :ok <- (if written do :ok else send_silence(state.sock, demanded_buffers) end)
    do
      {{:ok, demand: {:sink, {:set_to, demanded_buffers}}}, %{state | written: false}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @doc false
  def handle_stop(%{sock: nil} = state) do
    {:ok, %{state | next_tick: nil}}
  end

  def handle_stop(%{sock: sock} = state) do
    :ok = :gen_tcp.close(sock)
    {:ok, %{state | next_tick: nil, sock: nil}}
  end

  def handle_event(:sink, %Membrane.Event{type: :channel_added}, _, state) do
    info "new channel"
    {:ok, state}
  end
  def handle_event(:sink, %Membrane.Event{type: :channel_removed}, _, state) do
    info "end of channel"
    {:ok, state}
  end
  def handle_event(pad, event, ctx, state) do
    super(pad, event, ctx, state)
  end

  @doc false
  def handle_write1(:sink, _caps, _buffer, %{sock: nil}) do
    raise "Received buffer while not connected"
  end

  def handle_write1(:sink, %Buffer{payload: payload}, _caps, %{sock: sock} = state) do
    with :ok <- send_buffer(sock, payload) do
      not_written_time = Time.monotonic_time - state.written_time
      if not_written_time > 2*state.frame_duration do
        info "not written for #{not_written_time |> Time.to_milliseconds} ms"
      end
      {:ok, %{state | written_time: Time.monotonic_time, written: true}}
    else
      {:error, reason} ->
        {{:error, reason}, %{state | sock: nil}}
    end
  end

  #TODO: support other than default frame durations
  defp send_silence(_sock, 0), do: :ok
  defp send_silence(sock, size) when size > 0 do
    {payload, _caps} = Caps.sound_of_silence
    payload = Stream.repeatedly(fn -> payload end)
      |> Enum.take(size)
      |> IO.iodata_to_binary
    send_buffer(sock, payload)
  end

  defp send_buffer(sock, payload) do
    with :ok <- :gen_tcp.send(sock, payload) do
      :ok
    else
      {:error, reason} ->
        warn("Failed to send buffer: #{inspect(reason)}")
        :gen_tcp.close(sock)
        {:error, {:send_buffer_to_icecast, reason}}
    end
  end

end
