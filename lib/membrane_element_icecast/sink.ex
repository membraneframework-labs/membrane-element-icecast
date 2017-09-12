defmodule Membrane.Element.Icecast.Sink do
  use Membrane.Element.Base.Sink
  use Membrane.Mixins.Log
  alias Membrane.Time
  alias Membrane.Element.Icecast.Sink.Options
  alias Membrane.Buffer
  alias Membrane.Caps.Audio

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
    }}
  end


  @doc false
  def handle_play(%{host: host, port: port, connect_timeout: connect_timeout} = state) do
    case :gen_tcp.connect(to_charlist(host), port, [mode: :binary, packet: :line, active: false, keepalive: true], connect_timeout) do
      {:ok, sock} ->
        do_request(state, sock)

      {:error, reason} ->
        warn("Failed to connect to #{host}:#{port}: #{inspect(reason)}")
        {:error, {:connect, reason}, %{state | sock: nil}}
    end
  end

  defp do_request(%{host: host, mount: mount, password: password, request_timeout: request_timeout} = state, sock) do
    with credentials <- "source:#{password}" |> Base.encode64,
         {:request, :ok} <- {:request, :gen_tcp.send(sock, "SOURCE #{mount} HTTP/1.0\r\nAuthorization: Basic #{credentials}\r\nHost: #{host}\r\nUser-Agent: RadioKit Osmosis\r\nContent-Type: audio/mpeg\r\n\r\n")},
         {:response, {:ok, "HTTP/1.0 200 OK\r\n"}} <- {:response, :gen_tcp.recv(sock, 0, request_timeout)}
    do
      info("Got OK response")
      send self(), :tick
      first_tick = Time.monotonic_time()
      {:ok, %{state | sock: sock, first_tick: first_tick}}
    else
      {:request, {:error, reason}} ->
        warn("Failed to send request: #{inspect(reason)}")
        :ok = :gen_tcp.close(sock)
        {:error, {:request, reason}, %{state | sock: nil}}

      {:response, {:ok, response}} ->
        warn("Got unexpected response: #{inspect(response)}")
        :ok = :gen_tcp.close(sock)
        {:error, {:response, {:unexpected, response}}, %{state | sock: nil}}

      {:response, {:error, reason}} ->
        warn("Failed to receive response: #{inspect(reason)}")
        :ok = :gen_tcp.close(sock)
        {:error, {:response, reason}, %{state | sock: nil}}
    end
  end

  @doc false
  def handle_caps(:sink, %Audio.MPEG{sample_rate: sample_rate, version: version, layer: layer}, _params, state) do
    samples = Audio.MPEG.samples_per_frame(version, layer)
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
  def handle_other(:tick, %{first_tick: first_tick, tick_offset: tick_offset, frame_duration: frame_duration, demanded_buffers: demanded_buffers} = state) do
    new_offset = tick_offset + frame_duration * demanded_buffers
    next_tick = first_tick + round(new_offset)
    _timer_ref = Process.send_after(self(), :tick, Time.to_milliseconds(next_tick), abs: true)
    {{:ok, demand: {:sink, demanded_buffers}}, %{state | tick_offset: new_offset}}
  end

  @doc false
  def handle_stop(%{sock: nil} = state) do
    {:ok, %{state | next_tick: nil}}
  end

  def handle_stop(%{sock: sock} = state) do
    :ok = :gen_tcp.close(sock)
    {:ok, %{state | next_tick: nil, sock: nil}}
  end


  @doc false
  def handle_write1(:sink, _caps, _buffer, %{sock: nil} = state) do
    warn("Received buffer while not connected")
    {:ok, state}
  end

  def handle_write1(:sink, %Buffer{payload: payload}, _caps, %{sock: sock} = state) do
    case :gen_tcp.send(sock, payload) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        warn("Failed to send buffer: #{inspect(reason)}")
        :ok = :gen_tcp.close(sock)
        {:error, {:send, reason}, %{state | sock: nil}}
    end
  end
end
