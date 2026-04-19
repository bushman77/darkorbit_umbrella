defmodule Darkorbit.LoadoutsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Darkorbit.Loadouts` context.
  """

  @doc """
  Generate a player_ship_loadout.
  """
  def player_ship_loadout_fixture(attrs \\ %{}) do
    {:ok, player_ship_loadout} =
      attrs
      |> Enum.into(%{
        config_no: 42,
        drones: %{},
        generators: %{},
        lasers: %{}
      })
      |> Darkorbit.Loadouts.create_player_ship_loadout()

    player_ship_loadout
  end
end
