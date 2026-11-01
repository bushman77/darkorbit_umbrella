defmodule Core.NPC.Catalog do
  @moduledoc """
  Configurable catalog of original NPC definitions.

  Values are provisional balancing data. Deployments can replace the complete
  list with `config :core, :npc_catalog, definitions`.
  """

  alias Core.NPC.Definition
  alias Core.World.Position

  @default_definitions [
    %Definition{
      id: "rift_skirmisher",
      display_name: "Rift Skirmisher",
      max_hull: 800,
      max_shields: 400,
      shield_absorption: 0.6,
      movement_speed: 175,
      laser_damage: 45,
      attack_range: 420.0,
      attack_cooldown_ms: 1_200,
      detection_radius: 900.0,
      spawn: %{
        map_id: "1-1",
        positions: [
          %Position{x: 1_480.0, y: 1_000.0},
          %Position{x: 1_720.0, y: 1_320.0},
          %Position{x: 1_230.0, y: 1_620.0}
        ],
        patrol_radius: 240.0,
        respawn_delay_ms: 3_000
      }
    }
  ]

  @spec all() :: [Definition.t()]
  def all, do: Application.get_env(:core, :npc_catalog, @default_definitions)

  @spec for_map(String.t(), [Definition.t()]) :: [Definition.t()]
  def for_map(map_id, catalog \\ all()) when is_binary(map_id) do
    Enum.filter(catalog, &(&1.spawn.map_id == map_id))
  end

  @spec fetch(String.t(), [Definition.t()] | %{optional(String.t()) => Definition.t()}) ::
          {:ok, Definition.t()} | :error
  def fetch(id, catalog \\ all()) when is_binary(id) do
    case catalog do
      definitions when is_list(definitions) ->
        Enum.find_value(definitions, :error, &matching_definition(&1, id))

      definitions when is_map(definitions) ->
        Map.fetch(definitions, id)
    end
  end

  @spec fetch!(String.t(), [Definition.t()] | %{optional(String.t()) => Definition.t()}) ::
          Definition.t()
  def fetch!(id, catalog \\ all()) do
    case fetch(id, catalog) do
      {:ok, definition} -> definition
      :error -> raise KeyError, key: id, term: catalog
    end
  end

  defp matching_definition(%Definition{id: id} = definition, id), do: {:ok, definition}
  defp matching_definition(_definition, _id), do: false
end
