defmodule Darkorbit.ShipStatsTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Fleet
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts
  alias Darkorbit.ShipStats

  test "derives each configuration from its actually equipped inventory" do
    account = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(account.id)
    [configuration_one, configuration_two] = Loadouts.list_loadouts_for_player_ship(ship.id)

    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 1)
    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf4", 1)
    assert {:ok, _equipment} = Inventory.add_equipment(account.id, "g1", 1)
    assert {:ok, _equipment} = Inventory.add_equipment(account.id, "sg1", 1)

    assert {:ok, _loadout} =
             Loadouts.equip_laser_from_inventory(
               account.id,
               configuration_one.id,
               "ship",
               0,
               "lf1"
             )

    assert {:ok, _loadout} =
             Loadouts.equip_generator_from_inventory(
               account.id,
               configuration_one.id,
               "ship",
               0,
               "g1"
             )

    assert {:ok, _loadout} =
             Loadouts.equip_laser_from_inventory(
               account.id,
               configuration_two.id,
               "ship",
               0,
               "lf4"
             )

    assert {:ok, _loadout} =
             Loadouts.equip_generator_from_inventory(
               account.id,
               configuration_two.id,
               "ship",
               0,
               "sg1"
             )

    assert {:ok, config_one} = ShipStats.calculate(account.id, ship.id, 1)
    assert config_one.damage == 40
    assert config_one.speed == 322
    assert config_one.shields == 0

    assert {:ok, config_two} = ShipStats.for_active_ship(account.id, 2)
    assert config_two.damage == 200
    assert config_two.speed == 320
    assert config_two.shields == 1_000
  end

  test "does not expose another player's loadout" do
    owner = player_account_fixture()
    other_player = player_account_fixture()
    [ship] = Fleet.list_ships_for_user(owner.id)

    assert {:error, :loadout_not_found} = ShipStats.calculate(other_player.id, ship.id, 1)
  end
end
