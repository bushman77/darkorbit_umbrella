defmodule Core.NPC.Catalog do
  @moduledoc """
  Configurable NPC ship definitions, grounded where possible in the original
  Space Rogue recognition guide. Unimplemented weapons, directional shields,
  acceleration and ECM are not simulated yet.

  Sector 1-1 deliberately fields just one starter Dart at a time. This is a
  demo encounter, not the future faction/encounter spawning system.
  """

  alias Core.NPC.Definition
  alias Core.World.Position

  @default_definitions [
    %Definition{
      id: "dart",
      display_name: "Dart",
      # Original Space Rogue (1989): Pirate fighter, 12 m, 16 t,
      # 245 armor, Garnet laser, SM-1, Fwd-2 shields, 10% ECM,
      # Borelle propulsion, 0.30g acceleration, 45 deg/s turning.
      #
      # Only the original 245 armor is mapped 1:1 to current hull.
      # Current engine has generic rather than directional shields and
      # no separate missile, ECM or acceleration stats for NPCs.
      # The following values are provisional gameplay balancing:
      max_hull: 245,
      max_shields: 120,
      shield_absorption: 0.6,
      movement_speed: 210,
      laser_damage: 35,
      attack_range: 420.0,
      attack_cooldown_ms: 1_200,
      detection_radius: 900.0,
      spawn: %{
        map_id: "1-1",
        positions: [%Position{x: 1_480.0, y: 1_000.0}],
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
