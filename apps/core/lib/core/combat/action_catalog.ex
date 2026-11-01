defmodule Core.Combat.ActionCatalog do
  @moduledoc """
  Server-defined combat actions exposed through the player's action hotbar.

  Slots are data rather than transport-specific key handlers so later
  milestones can replace empty entries with ammunition, rockets, abilities,
  consumables, or equipment-owned actions.
  """

  @slot_count 10
  @pulse_emitter %{
    id: "pulse_emitter",
    kind: :weapon,
    label: "Pulse emitter",
    icon: "pulse",
    cooldown_ms: 700
  }

  @type action :: %{
          id: String.t(),
          kind: atom(),
          label: String.t(),
          icon: String.t(),
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

  @spec pulse_emitter() :: action()
  def pulse_emitter, do: @pulse_emitter

  defp action_for_slot(1), do: @pulse_emitter
  defp action_for_slot(_slot), do: nil

  defp slot_key(10), do: "0"
  defp slot_key(slot), do: Integer.to_string(slot)
end
