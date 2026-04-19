defmodule Darkorbit.FleetFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Fleet` context.
  """

  @doc """
  Generate a player_ship.
  """
  def player_ship_fixture(attrs \\ %{}) do
    {:ok, player_ship} =
      attrs
      |> Enum.into(%{
        ship_id: 42
      })
      |> Darkorbit.Fleet.create_player_ship()

    player_ship
  end
end
