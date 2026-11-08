defmodule Core.World.Entity do
  @moduledoc "Authoritative runtime state for one connected player ship."

  alias Core.World.Position

  @enforce_keys [
    :id,
    :kind,
    :player_id,
    :session_id,
    :position,
    :speed,
    :hull,
    :max_hull,
    :shields,
    :max_shields,
    :shield_absorption,
    :damage,
    :attack_range,
    :attack_cooldown_ticks,
    :next_attack_tick,
    :status
  ]
  defstruct @enforce_keys ++ [
              :ship_instance_id,
              :destination,
              :target_id,
              :engaged_target_id,
              docked: false,
              navigation_mode: :manual,
              route_waypoints: [],
              flight_mode: :cruise,
              throttle: 0.0,
              cruise_speed: 0.0,
              attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0},
              orientation: nil,
              rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0},
              angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0},
              velocity: %{x: 0.0, y: 0.0, z: 0.0},
              control_tick: -1_000
            ]

  @type t :: %__MODULE__{
          id: term(),
          ship_instance_id: pos_integer() | nil,
          kind: :player,
          player_id: term(),
          session_id: pos_integer(),
          position: Position.t(),
          destination: Position.t() | nil,
          navigation_mode: :manual | :autopilot,
          route_waypoints: [Position.t()],
          flight_mode: :cruise | :newtonian,
          throttle: float(),
          cruise_speed: float(),
          attitude: %{yaw: float(), pitch: float(), roll: float()},
          orientation: Core.World.Orientation.t() | nil,
          rotation_input: %{yaw: float(), pitch: float(), roll: float()},
          angular_velocity: %{yaw: float(), pitch: float(), roll: float()},
          velocity: %{x: float(), y: float(), z: float()},
          control_tick: integer(),
          speed: number(),
          hull: non_neg_integer(),
          max_hull: non_neg_integer(),
          shields: non_neg_integer(),
          max_shields: non_neg_integer(),
          shield_absorption: float(),
          damage: non_neg_integer(),
          attack_range: number(),
          attack_cooldown_ticks: pos_integer(),
          next_attack_tick: non_neg_integer(),
          target_id: term() | nil,
          engaged_target_id: term() | nil,
          docked: boolean(),
          status: :alive | :destroyed
        }
end
