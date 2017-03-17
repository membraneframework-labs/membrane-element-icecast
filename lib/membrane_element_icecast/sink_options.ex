defmodule Membrane.Element.Icecast.Sink.Options do
  @type host_t :: String.t
  @type port_t :: pos_integer
  @type password_t :: String.t
  @type mount_t :: String.t
  @type connect_timeout_t :: pos_integer
  @type request_timeout_t :: pos_integer | :infinity

  @type t :: %Membrane.Element.Icecast.Sink.Options{
    host: host_t,
    port: port_t,
    password: password_t,
    mount: mount_t,
    connect_timeout: connect_timeout_t,
    request_timeout: request_timeout_t,
  }

  defstruct \
    host: nil,
    port: nil,
    password: nil,
    mount: nil,
    connect_timeout: 5000,
    request_timeout: 5000
end
