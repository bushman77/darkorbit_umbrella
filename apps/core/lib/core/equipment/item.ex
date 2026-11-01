defmodule Core.Equipment.Item do
  @moduledoc """
  A catalog definition for an equippable item.

  Categories determine the compatible loadout slot. Numeric effects remain
  data so the statistics calculator has no item-id-specific branches.
  """

  @enforce_keys [:id, :name, :category]
  defstruct [
    :id,
    :name,
    :category,
    damage: 0,
    damage_multiplier: 1.0,
    speed: 0,
    shields: 0,
    shield_absorption: 0.0,
    shield_regeneration: 0
  ]

  @type category :: :laser | :generator | :shield

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          category: category(),
          damage: non_neg_integer(),
          damage_multiplier: float(),
          speed: non_neg_integer(),
          shields: non_neg_integer(),
          shield_absorption: float(),
          shield_regeneration: non_neg_integer()
        }
end
