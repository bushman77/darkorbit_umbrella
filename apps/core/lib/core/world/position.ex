defmodule Core.World.Position do
  @moduledoc "Server-owned XYZ coordinates; XY are the top-down atlas plane."

  @enforce_keys [:x, :y]
  defstruct [:x, :y, z: 0.0]

  @type coordinate :: number()
  @type t :: %__MODULE__{x: coordinate(), y: coordinate(), z: coordinate()}
end
