defmodule Darkorbit.FleetTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Fleet
  alias Darkorbit.Loadouts

  test "adding a ship is atomic and idempotent with two configurations" do
    account = player_account_fixture()

    assert {:ok, ship} = Fleet.add_ship_to_user(account.id, 2)
    assert {:ok, same_ship} = Fleet.add_ship_to_user(account.id, 2)
    assert same_ship.id == ship.id
    assert Fleet.owned_ship?(account.id, 2)

    assert [configuration_one, configuration_two] =
             Loadouts.list_loadouts_for_player_ship(ship.id)

    assert configuration_one.config_no == 1
    assert configuration_two.config_no == 2
    assert length(Fleet.list_ships_for_user(account.id)) == 2
  end

  test "rejects invalid ship definitions without creating ownership" do
    account = player_account_fixture()

    assert {:error, %Ecto.Changeset{}} = Fleet.add_ship_to_user(account.id, 0)
    refute Fleet.owned_ship?(account.id, 0)
  end

  test "active ship changes require ownership" do
    account = player_account_fixture()

    assert {:error, :ship_not_owned} = Fleet.change_active_ship(account.id, 2)
    assert {:ok, _ship} = Fleet.add_ship_to_user(account.id, 2)
    assert {:ok, updated_account} = Fleet.change_active_ship(account.id, 2)
    assert updated_account.ship_id == 2
  end
end
