defmodule Core.Ships.Ship do
  @moduledoc """
  Immutable base statistics and equipment capacities for a ship definition.

  Ship definitions are game data. Player ownership and equipped items live in
  the persistence application and are deliberately not represented here.
  """

  @enforce_keys [
    :id,
    :name,
    :hit_points,
    :shields,
    :speed,
    :damage,
    :cargo_capacity,
    :laser_slots,
    :generator_slots
  ]
  defstruct [
    :id,
    :name,
    :hit_points,
    :shields,
    :speed,
    :damage,
    :cargo_capacity,
    :laser_slots,
    :generator_slots,
    damage_multiplier: 1.0,
    shield_absorption: 0.0,
    shield_regeneration: 0,
    forward_shield_class: 0,
    aft_shield_class: 0,
    missile_tube: false,
    acceleration_g: nil,
    turn_deg_s: nil,
    cargo_pods: 0,
    max_cargo_pods: 0
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          hit_points: non_neg_integer(),
          shields: non_neg_integer(),
          speed: non_neg_integer(),
          damage: non_neg_integer(),
          cargo_capacity: non_neg_integer(),
          laser_slots: non_neg_integer(),
          generator_slots: non_neg_integer(),
          damage_multiplier: float(),
          shield_absorption: float(),
          shield_regeneration: non_neg_integer(),
          forward_shield_class: non_neg_integer(),
          aft_shield_class: non_neg_integer(),
          missile_tube: boolean(),
          acceleration_g: number() | nil,
          turn_deg_s: number() | nil,
          cargo_pods: non_neg_integer(),
          max_cargo_pods: non_neg_integer()
        }
end
