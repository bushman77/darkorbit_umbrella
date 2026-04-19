defmodule Darkorbit.FleetTest do
  use Darkorbit.DataCase

  alias Darkorbit.Fleet

  describe "player_ships" do
    alias Darkorbit.Fleet.PlayerShip

    import Darkorbit.FleetFixtures

    @invalid_attrs %{ship_id: nil}

    test "list_player_ships/0 returns all player_ships" do
      player_ship = player_ship_fixture()
      assert Fleet.list_player_ships() == [player_ship]
    end

    test "get_player_ship!/1 returns the player_ship with given id" do
      player_ship = player_ship_fixture()
      assert Fleet.get_player_ship!(player_ship.id) == player_ship
    end

    test "create_player_ship/1 with valid data creates a player_ship" do
      valid_attrs = %{ship_id: 42}

      assert {:ok, %PlayerShip{} = player_ship} = Fleet.create_player_ship(valid_attrs)
      assert player_ship.ship_id == 42
    end

    test "create_player_ship/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Fleet.create_player_ship(@invalid_attrs)
    end

    test "update_player_ship/2 with valid data updates the player_ship" do
      player_ship = player_ship_fixture()
      update_attrs = %{ship_id: 43}

      assert {:ok, %PlayerShip{} = player_ship} = Fleet.update_player_ship(player_ship, update_attrs)
      assert player_ship.ship_id == 43
    end

    test "update_player_ship/2 with invalid data returns error changeset" do
      player_ship = player_ship_fixture()
      assert {:error, %Ecto.Changeset{}} = Fleet.update_player_ship(player_ship, @invalid_attrs)
      assert player_ship == Fleet.get_player_ship!(player_ship.id)
    end

    test "delete_player_ship/1 deletes the player_ship" do
      player_ship = player_ship_fixture()
      assert {:ok, %PlayerShip{}} = Fleet.delete_player_ship(player_ship)
      assert_raise Ecto.NoResultsError, fn -> Fleet.get_player_ship!(player_ship.id) end
    end

    test "change_player_ship/1 returns a player_ship changeset" do
      player_ship = player_ship_fixture()
      assert %Ecto.Changeset{} = Fleet.change_player_ship(player_ship)
    end
  end
end
