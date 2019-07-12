defmodule Membrane.Element.Icecast.Source do
  use Membrane.Element.Base.Source

  def_output_pads output: [
    caps: :any
  ]

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) do
    {:ok, state}
  end
end
