defmodule Membrane.Element.Icecast.Sink.Options do
  @moduledoc false

  @type host_t :: String.t
  @type port_t :: pos_integer
  @type password_t :: String.t
  @type mount_t :: String.t
  @type connect_timeout_t :: pos_integer
  @type request_timeout_t :: pos_integer | :infinity
  @type demand_size_t :: pos_integer

  @type t :: %Membrane.Element.Icecast.Sink.Options{
    host: host_t,
    port: port_t,
    password: password_t,
    mount: mount_t,
    connect_timeout: connect_timeout_t,
    request_timeout: request_timeout_t,
    demand_size: demand_size_t,
  }

  defstruct \
    host: nil,
    port: nil,
    password: nil,
    mount: nil,
    connect_timeout: 5000,
    request_timeout: 5000,
    demand_size: 2048
end
