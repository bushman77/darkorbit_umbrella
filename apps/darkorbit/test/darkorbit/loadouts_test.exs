defmodule Darkorbit.LoadoutsTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts

  test "equipping, replacing, and unequipping preserve equipment" do
    account = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(account.id)
    [configuration_one, _configuration_two] = Loadouts.list_loadouts_for_player_ship(ship.id)

    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)

    assert {:ok, equipped} =
             Loadouts.equip_laser_from_inventory(
               account.id,
               configuration_one.id,
               "ship",
               0,
               "lf1"
             )

    assert Enum.at(equipped.lasers["ship"], 0) == "lf1"
    assert Inventory.laser_count(account.id, "lf1") == 0

    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf2", 1)

    assert {:ok, replaced} =
             Loadouts.equip_laser_from_inventory(
               account.id,
               configuration_one.id,
               "ship",
               0,
               "lf2"
             )

    assert Enum.at(replaced.lasers["ship"], 0) == "lf2"
    assert Inventory.laser_count(account.id, "lf1") == 1
    assert Inventory.laser_count(account.id, "lf2") == 0

    assert {:ok, unequipped} =
             Loadouts.unequip_laser_to_inventory(
               account.id,
               configuration_one.id,
               "ship",
               0
             )

    assert Enum.at(unequipped.lasers["ship"], 0) == nil
    assert Inventory.laser_count(account.id, "lf2") == 1
  end

  test "validates slot bounds and capacity before consuming inventory" do
    account = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(account.id)
    [loadout | _rest] = Loadouts.list_loadouts_for_player_ship(ship.id)
    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)

    assert {:error, :invalid_slot} =
             Loadouts.equip_laser_from_inventory(account.id, loadout.id, "ship", -1, "lf1")

    assert {:error, :slot_locked} =
             Loadouts.equip_laser_from_inventory(account.id, loadout.id, "ship", 1, "lf1")

    assert {:error, :invalid_location} =
             Loadouts.equip_laser_from_inventory(account.id, loadout.id, "cargo", 0, "lf1")

    assert Inventory.laser_count(account.id, "lf1") == 1
  end

  test "requires the acting account to own the loadout" do
    owner = player_account_fixture()
    attacker = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(owner.id)
    [loadout | _rest] = Loadouts.list_loadouts_for_player_ship(ship.id)
    assert {:ok, _equipment} = Inventory.add_lasers(attacker.id, "lf1", 1)

    assert {:error, :loadout_not_found} =
             Loadouts.equip_laser_from_inventory(
               attacker.id,
               loadout.id,
               "ship",
               0,
               "lf1"
             )

    assert Inventory.laser_count(attacker.id, "lf1") == 1
    persisted = Loadouts.get_player_ship_loadout!(loadout.id)
    assert Enum.at(persisted.lasers["ship"], 0) == nil
  end

  test "re-equipping the same laser is idempotent" do
    account = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(account.id)
    [loadout | _rest] = Loadouts.list_loadouts_for_player_ship(ship.id)
    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)

    assert {:ok, _loadout} =
             Loadouts.equip_laser_from_inventory(account.id, loadout.id, "ship", 0, "lf1")

    assert {:ok, _loadout} =
             Loadouts.equip_laser_from_inventory(account.id, loadout.id, "ship", 0, "lf1")

    assert Inventory.laser_count(account.id, "lf1") == 0
  end
end
