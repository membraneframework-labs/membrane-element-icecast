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
      next_tick: nil,
    }}
  end


  @doc false
  def handle_play(%{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout} = state) do
    case :gen_tcp.connect(to_charlist(host), port, [mode: :binary, packet: :line, active: false, keepalive: true], connect_timeout) do
      {:ok, sock} ->
        info("Connected to #{host}:#{port}")

        credentials = "source:#{password}" |> Base.encode64

        case :gen_tcp.send(sock, "SOURCE #{mount} HTTP/1.0\r\nAuthorization: Basic #{credentials}\r\nHost: #{host}\r\nUser-Agent: RadioKit Osmosis\r\nContent-Type: audio/mpeg\r\n\r\n") do
          :ok ->
            info("Sent request")
            case :gen_tcp.recv(sock, 0, request_timeout) do
              {:ok, "HTTP/1.0 200 OK\r\n"} ->
                info("Got OK response")
                send self(), :tick
                last_tick = Time.monotonic_time()
                {:ok, %{state | sock: sock, next_tick: last_tick}}

              {:ok, response} ->
                warn("Got unexpected response: #{inspect(response)}")
                :ok = :gen_tcp.close(sock)
                {:error, {:response, {:unexpected, response}}, %{state | sock: nil}}

              {:error, reason} ->
                warn("Failed to receive response: #{inspect(reason)}")
                :ok = :gen_tcp.close(sock)
                {:error, {:response, reason}, %{state | sock: nil}}
            end

          {:error, reason} ->
            warn("Failed to send request: #{inspect(reason)}")
            :ok = :gen_tcp.close(sock)
            {:error, {:request, reason}, %{state | sock: nil}}
        end

      {:error, reason} ->
        warn("Failed to connect to #{host}:#{port}: #{inspect(reason)}")
        {:error, {:connect, reason}, %{state | sock: nil}}
    end
  end

  @doc false
  def handle_caps(:sink, %Audio.MPEG{sample_rate: sample_rate, version: version, layer: layer}, _params, state) do
    samples = Audio.MPEG.samples_per_frame(version, layer)
    frame_duration = (1 |> Time.second |> Time.to_nanoseconds) * samples / sample_rate
    debug("New frame duration #{frame_duration}")
    {:ok, %{state | frame_duration: frame_duration}}
  end

  @doc false
  def handle_other(:tick, %{next_tick: this_tick, frame_duration: frame_duration, demanded_buffers: demanded_buffers} = state) do
    next_tick = this_tick + round(frame_duration * demanded_buffers)
    _timer_ref = Process.send_after(self(), :tick, Time.to_milliseconds(next_tick), abs: true)
    {{:ok, demand: {:sink, demanded_buffers}}, %{state | next_tick: next_tick}}
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
