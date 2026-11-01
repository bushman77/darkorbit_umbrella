defmodule Core.NPC.Definition do
  @moduledoc "Configurable, transport-neutral definition for an NPC type."

  alias Core.World.Position

  @enforce_keys [
    :id,
    :display_name,
    :max_hull,
    :max_shields,
    :shield_absorption,
    :movement_speed,
    :laser_damage,
    :attack_range,
    :attack_cooldown_ms,
    :detection_radius,
    :spawn
  ]
  defstruct @enforce_keys

  @type spawn_config :: %{
          required(:map_id) => String.t(),
          required(:positions) => [Position.t()],
          required(:patrol_radius) => number(),
          required(:respawn_delay_ms) => pos_integer()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t(),
          max_hull: pos_integer(),
          max_shields: non_neg_integer(),
          shield_absorption: float(),
          movement_speed: non_neg_integer(),
          laser_damage: non_neg_integer(),
          attack_range: number(),
          attack_cooldown_ms: pos_integer(),
          detection_radius: number(),
          spawn: spawn_config()
        }
end
