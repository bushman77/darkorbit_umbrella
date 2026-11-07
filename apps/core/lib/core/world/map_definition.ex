defmodule Core.World.MapDefinition do
  @moduledoc """
  Static boundaries and spawn data for a playable world map.
  """

  alias Core.World.Position

  @starting_map_id "1-1"

  @enforce_keys [:id, :name, :width, :height, :spawn]
  defstruct [:id, :name, :width, :height, :spawn,
             altitude_min: -3_000, altitude_max: 3_000, planet: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          altitude_min: number(),
          altitude_max: number(),
          planet: map() | nil,
          spawn: Position.t()
        }

  @spec starting_map_id() :: String.t()
  def starting_map_id, do: @starting_map_id

  @spec starting_map() :: t()
  def starting_map do
    %__MODULE__{
      id: @starting_map_id,
      name: "Home Sector",
      width: 20_000,
      height: 12_000,
      spawn: %Position{x: 1_000.0, y: 1_000.0}
    }
  end

  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = definition), do: definition

  def new(definition) when is_map(definition) do
    %__MODULE__{
      id: fetch_value!(definition, :id),
      name: fetch_value!(definition, :name),
      width: fetch_value!(definition, :width),
      height: fetch_value!(definition, :height),
      altitude_min: optional_value(definition, :altitude_min, -3_000),
      altitude_max: optional_value(definition, :altitude_max, 3_000),
      planet: optional_value(definition, :planet, nil),
      spawn: position(fetch_value!(definition, :spawn))
    }
  end

  defp position(%Position{} = position), do: position
  defp position({x, y, z}), do: %Position{x: x, y: y, z: z}
  defp position({x, y}), do: %Position{x: x, y: y}
  defp position(%{x: x, y: y} = input),
    do: %Position{x: x, y: y, z: Map.get(input, :z, 0.0)}
  defp position(%{"x" => x, "y" => y} = input),
    do: %Position{x: x, y: y, z: Map.get(input, "z", 0.0)}

  defp optional_value(map, key, default),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp fetch_value!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(map, Atom.to_string(key))
    end
  end
end
