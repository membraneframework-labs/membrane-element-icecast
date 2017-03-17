defmodule Membrane.Element.Icecast.Sink do
  use Membrane.Element.Base.Sink
  use Membrane.Mixins.Log
  alias Membrane.Element.Icecast.Sink.Options


  def_known_sink_pads %{
    :sink => {:always, [
      %Membrane.Caps.Audio.MPEG{}
    ]}
  }


  # Private API

  @doc false
  def handle_init(%Options{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout}) do
    {:ok, %{
      sock: nil,
      host: host,
      port: port,
      mount: mount,
      password: password,
      connect_timeout: connect_timeout,
      request_timeout: request_timeout,
    }}
  end


  @doc false
  def handle_play(%{host: host, port: port, mount: mount, password: password, connect_timeout: connect_timeout, request_timeout: request_timeout} = state) do
    case :gen_tcp.connect(to_char_list(host), port, [mode: :binary, packet: :line, active: false, keepalive: true], connect_timeout) do
      {:ok, sock} ->
        info("Connected to #{host}:#{port}")

        credentials = "source:#{password}" |> Base.encode64

        case :gen_tcp.send(sock, "SOURCE #{mount} HTTP/1.0\r\nAuthorization: Basic #{credentials}\r\nHost: #{host}\r\nUser-Agent: RadioKit Osmosis\r\nContent-Type: audio/mpeg\r\n\r\n") do
          :ok ->
            info("Sent request")
            case :gen_tcp.recv(sock, 0, request_timeout) do
              {:ok, "HTTP/1.0 200 OK\r\n"} ->
                info("Got OK response")
                {:ok, %{state | sock: sock}}

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
  def handle_stop(%{sock: nil} = state) do
    {:ok, state}
  end

  def handle_stop(%{sock: sock} = state) do
    :ok = :gen_tcp.close(sock)
    {:ok, %{state | sock: nil}}
  end


  @doc false
  def handle_buffer(:sink, _caps, _buffer, %{sock: nil} = state) do
    warn("Received buffer while not connected")
    {:ok, state}
  end

  def handle_buffer(:sink, _caps, %Membrane.Buffer{payload: payload}, %{sock: sock} = state) do
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
