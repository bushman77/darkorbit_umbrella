defmodule Darkorbit.InventoryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Inventory` context.
  """

  @doc """
  Generate a player_equipment.
  """
  def player_equipment_fixture(attrs \\ %{}) do
    {:ok, player_equipment} =
      attrs
      |> Enum.into(%{
        items: %{},
        skill_points: %{}
      })
      |> Darkorbit.Inventory.create_player_equipment()

    player_equipment
  end
end
