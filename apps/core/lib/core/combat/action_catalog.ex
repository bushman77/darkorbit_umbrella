defmodule Core.Combat.ActionCatalog do
  @moduledoc """
  Server-defined combat actions exposed through the player's action hotbar.

  Slots are data rather than transport-specific key handlers. Every assigned
  action declares what it is and how activation behaves so later milestones
  can add ammunition, rockets, abilities, consumables, or equipment-owned
  actions without teaching clients about individual slot numbers.
  """

  @slot_count 10
  @pulse_emitter %{
    id: "pulse_emitter",
    type: :weapon,
    label: "Phoenix pulse emitter",
    cooldown_ms: 700
  }

  @x1_laser %{
    id: "x1_laser",
    type: :ammunition,
    activation_mode: :toggle,
    label: "X1 laser",
    icon: "laser",
    weapon_id: "pulse_emitter"
  }

  @type activation_mode :: :toggle | :single_use | :selection

  @type action_type :: :ammunition | :rocket | :ability | :consumable | :equipment

  @type action :: %{
          required(:id) => String.t(),
          required(:type) => action_type(),
          required(:activation_mode) => activation_mode(),
          required(:label) => String.t(),
          required(:icon) => String.t(),
          optional(:weapon_id) => String.t()
        }

  @type weapon :: %{
          id: String.t(),
          type: :weapon,
          label: String.t(),
          cooldown_ms: pos_integer()
        }

  @type slot :: %{slot: 1..10, key: String.t(), action: action() | nil}

  @spec hotbar() :: [slot()]
  def hotbar do
    Enum.map(1..@slot_count, fn slot ->
      %{slot: slot, key: slot_key(slot), action: action_for_slot(slot)}
    end)
  end

  @spec fetch_slot(term()) :: {:ok, action() | nil} | {:error, :invalid_action_slot}
  def fetch_slot(slot) when is_integer(slot) and slot in 1..@slot_count do
    {:ok, action_for_slot(slot)}
  end

  def fetch_slot(_slot), do: {:error, :invalid_action_slot}

  @spec pulse_emitter() :: weapon()
  def pulse_emitter, do: @pulse_emitter

  @spec x1_laser() :: action()
  def x1_laser, do: @x1_laser

  defp action_for_slot(1), do: @x1_laser
  defp action_for_slot(_slot), do: nil

  defp slot_key(10), do: "0"
  defp slot_key(slot), do: Integer.to_string(slot)
end
