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
  def handle_init(%Options{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout, demanded_buffers: demanded_buffers}) do
    {:ok, %{
      sock: nil,
      host: host,
      port: port,
      mount: mount,
      password: password,
      connect_timeout: connect_timeout,
      request_timeout: request_timeout,
      demanded_buffers: demanded_buffers,
      start_time: nil,
      frame_duration: 26 |> Time.milliseconds |> Time.to_nanoseconds,
    }}
  end


  @doc false
  def handle_play(%{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout} = state) do
    start_time = Time.monotonic_time()
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
                {:ok, %{state | sock: sock, start_time: start_time}}

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
    frame_duration = (1 |> Time.second |> Time.to_nanoseconds) * samples |> div(sample_rate)
    {:ok, %{state | frame_duration: frame_duration}}
  end

  @doc false
  def handle_other(:tick, %{start_time: start_time, frame_duration: frame_duration, demanded_buffers: demanded_buffers} = state) do
    time_interval = frame_duration * demanded_buffers
    # Adjust next time to compensate for fact, that tick will be sent with additional delay
    next_tick = time_interval - ((Time.monotonic_time() - start_time) |> rem(time_interval))
    warn(next_tick)
    _timer_ref = Process.send_after(self(), :tick, Time.to_milliseconds(next_tick))
    {{:ok, demand: {:sink, demanded_buffers}}, state}
  end

  @doc false
  def handle_stop(%{sock: nil} = state) do
    {:ok, state}
  end

  def handle_stop(%{sock: sock} = state) do
    :ok = :gen_tcp.close(sock)
    {:ok, %{state | sock: nil}}
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
