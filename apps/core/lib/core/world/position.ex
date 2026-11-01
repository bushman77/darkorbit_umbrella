defmodule Core.World.Position do
  @moduledoc "Server-owned two-dimensional world coordinates."

  @enforce_keys [:x, :y]
  defstruct [:x, :y]

  @type coordinate :: number()
  @type t :: %__MODULE__{x: coordinate(), y: coordinate()}
end
