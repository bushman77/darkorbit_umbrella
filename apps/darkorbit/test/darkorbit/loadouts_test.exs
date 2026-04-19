defmodule Darkorbit.LoadoutsTest do
  use Darkorbit.DataCase

  alias Darkorbit.Loadouts

  describe "player_ship_loadouts" do
    alias Darkorbit.Loadouts.PlayerShipLoadout

    import Darkorbit.LoadoutsFixtures

    @invalid_attrs %{generators: nil, config_no: nil, lasers: nil, drones: nil}

    test "list_player_ship_loadouts/0 returns all player_ship_loadouts" do
      player_ship_loadout = player_ship_loadout_fixture()
      assert Loadouts.list_player_ship_loadouts() == [player_ship_loadout]
    end

    test "get_player_ship_loadout!/1 returns the player_ship_loadout with given id" do
      player_ship_loadout = player_ship_loadout_fixture()
      assert Loadouts.get_player_ship_loadout!(player_ship_loadout.id) == player_ship_loadout
    end

    test "create_player_ship_loadout/1 with valid data creates a player_ship_loadout" do
      valid_attrs = %{generators: %{}, config_no: 42, lasers: %{}, drones: %{}}

      assert {:ok, %PlayerShipLoadout{} = player_ship_loadout} = Loadouts.create_player_ship_loadout(valid_attrs)
      assert player_ship_loadout.generators == %{}
      assert player_ship_loadout.config_no == 42
      assert player_ship_loadout.lasers == %{}
      assert player_ship_loadout.drones == %{}
    end

    test "create_player_ship_loadout/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Loadouts.create_player_ship_loadout(@invalid_attrs)
    end

    test "update_player_ship_loadout/2 with valid data updates the player_ship_loadout" do
      player_ship_loadout = player_ship_loadout_fixture()
      update_attrs = %{generators: %{}, config_no: 43, lasers: %{}, drones: %{}}

      assert {:ok, %PlayerShipLoadout{} = player_ship_loadout} = Loadouts.update_player_ship_loadout(player_ship_loadout, update_attrs)
      assert player_ship_loadout.generators == %{}
      assert player_ship_loadout.config_no == 43
      assert player_ship_loadout.lasers == %{}
      assert player_ship_loadout.drones == %{}
    end

    test "update_player_ship_loadout/2 with invalid data returns error changeset" do
      player_ship_loadout = player_ship_loadout_fixture()
      assert {:error, %Ecto.Changeset{}} = Loadouts.update_player_ship_loadout(player_ship_loadout, @invalid_attrs)
      assert player_ship_loadout == Loadouts.get_player_ship_loadout!(player_ship_loadout.id)
    end

    test "delete_player_ship_loadout/1 deletes the player_ship_loadout" do
      player_ship_loadout = player_ship_loadout_fixture()
      assert {:ok, %PlayerShipLoadout{}} = Loadouts.delete_player_ship_loadout(player_ship_loadout)
      assert_raise Ecto.NoResultsError, fn -> Loadouts.get_player_ship_loadout!(player_ship_loadout.id) end
    end

    test "change_player_ship_loadout/1 returns a player_ship_loadout changeset" do
      player_ship_loadout = player_ship_loadout_fixture()
      assert %Ecto.Changeset{} = Loadouts.change_player_ship_loadout(player_ship_loadout)
    end
  end
end
