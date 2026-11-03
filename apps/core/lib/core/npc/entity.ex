defmodule Core.NPC.Entity do
  @moduledoc "Authoritative runtime state for one map-owned NPC."

  alias Core.Combat
  alias Core.NPC.Definition
  alias Core.World.Position

  @enforce_keys [
    :id,
    :kind,
    :npc_type_id,
    :display_name,
    :spawn_index,
    :position,
    :home_position,
    :speed,
    :hull,
    :max_hull,
    :shields,
    :max_shields,
    :shield_absorption,
    :damage,
    :attack_range,
    :attack_cooldown_ticks,
    :respawn_delay_ticks,
    :detection_radius,
    :patrol_radius,
    :state,
    :status,
    :next_attack_tick,
    :patrol_step
  ]
  defstruct @enforce_keys ++ [:destination, :target_id, :course]

  @type state :: :idle | :patrol | :pursue | :attack | :cruise | :destroyed

  @type t :: %__MODULE__{
          id: String.t(),
          kind: :npc,
          npc_type_id: String.t(),
          display_name: String.t(),
          spawn_index: non_neg_integer(),
          position: Position.t(),
          home_position: Position.t(),
          destination: Position.t() | nil,
          course: map() | nil,
          speed: number(),
          hull: non_neg_integer(),
          max_hull: pos_integer(),
          shields: non_neg_integer(),
          max_shields: non_neg_integer(),
          shield_absorption: float(),
          damage: non_neg_integer(),
          attack_range: number(),
          attack_cooldown_ticks: pos_integer(),
          respawn_delay_ticks: pos_integer(),
          detection_radius: number(),
          patrol_radius: number(),
          target_id: term() | nil,
          state: state(),
          status: :alive | :destroyed,
          next_attack_tick: non_neg_integer(),
          patrol_step: non_neg_integer()
        }

  @spec spawn(Definition.t(), non_neg_integer(), pos_integer()) :: t()
  def spawn(%Definition{} = definition, spawn_index, tick_ms)
      when is_integer(spawn_index) and spawn_index >= 0 do
    position = Enum.fetch!(definition.spawn.positions, spawn_index)

    %__MODULE__{
      id: entity_id(definition, spawn_index),
      kind: :npc,
      npc_type_id: definition.id,
      display_name: definition.display_name,
      spawn_index: spawn_index,
      position: position,
      home_position: position,
      destination: nil,
      course: nil,
      speed: definition.movement_speed,
      hull: definition.max_hull,
      max_hull: definition.max_hull,
      shields: definition.max_shields,
      max_shields: definition.max_shields,
      shield_absorption: definition.shield_absorption,
      damage: definition.laser_damage,
      attack_range: definition.attack_range,
      attack_cooldown_ticks: Combat.cooldown_ticks(definition.attack_cooldown_ms, tick_ms),
      respawn_delay_ticks: Combat.cooldown_ticks(definition.spawn.respawn_delay_ms, tick_ms),
      detection_radius: definition.detection_radius,
      patrol_radius: definition.spawn.patrol_radius,
      target_id: nil,
      state: :idle,
      status: :alive,
      next_attack_tick: 0,
      patrol_step: 0
    }
  end

  @spec entity_id(Definition.t(), non_neg_integer()) :: String.t()
  def entity_id(%Definition{} = definition, spawn_index) do
    "npc:#{definition.spawn.map_id}:#{definition.id}:#{spawn_index + 1}"
  end
end
