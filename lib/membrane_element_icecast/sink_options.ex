defmodule Membrane.Element.Icecast.Sink.Options do
  @moduledoc false

  @type host_t :: String.t
  @type port_t :: pos_integer
  @type password_t :: String.t
  @type mount_t :: String.t
  @type connect_timeout_t :: pos_integer
  @type request_timeout_t :: pos_integer | :infinity
  @type frame_duration_t :: float

  @type t :: %Membrane.Element.Icecast.Sink.Options{
    host: host_t,
    port: port_t,
    password: password_t,
    mount: mount_t,
    connect_timeout: connect_timeout_t,
    request_timeout: request_timeout_t,
    frame_duration: frame_duration_t,
  }

  defstruct \
    host: nil,
    port: nil,
    password: nil,
    mount: nil,
    connect_timeout: 5000,
    request_timeout: 5000,
    # frame_duration of MPEG v1 layer 2 in ns
    frame_duration: 1_000_000_000 / 44_100 * 1152
end
