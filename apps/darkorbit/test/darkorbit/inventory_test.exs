defmodule Darkorbit.InventoryTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Inventory

  test "adds and removes laser stacks without allowing negative quantities" do
    account = player_account_fixture()

    assert Inventory.laser_count(account.id, "lf1") == 0
    assert {:ok, _equipment} = Inventory.add_lasers(account.id, "lf1", 3)
    assert Inventory.laser_count(account.id, "lf1") == 3
    assert {:ok, _equipment} = Inventory.remove_laser(account.id, "lf1", 2)
    assert Inventory.laser_count(account.id, "lf1") == 1

    assert {:error, :not_enough_lasers} = Inventory.remove_laser(account.id, "lf1", 2)
    assert Inventory.laser_count(account.id, "lf1") == 1
  end

  test "rejects unknown equipment and invalid quantities" do
    account = player_account_fixture()

    assert {:error, :invalid_laser} = Inventory.add_lasers(account.id, "unknown", 1)
    assert {:error, :invalid_amount} = Inventory.add_lasers(account.id, "lf1", 0)
    assert {:error, :invalid_amount} = Inventory.remove_laser(account.id, "lf1", -1)
  end

  test "stores lasers, speed generators, and shields in catalog-owned buckets" do
    account = player_account_fixture()

    assert {:ok, _equipment} = Inventory.add_equipment(account.id, "g1", 2)
    assert {:ok, _equipment} = Inventory.add_equipment(account.id, "sg1", 1)
    assert Inventory.equipment_count(account.id, "g1") == 2
    assert Inventory.equipment_count(account.id, "sg1") == 1

    assert {:ok, _equipment} = Inventory.remove_equipment(account.id, "g1", 1)
    assert Inventory.equipment_count(account.id, "g1") == 1

    assert {:error, :not_enough_equipment} =
             Inventory.remove_equipment(account.id, "sg1", 2)
  end

  test "rejects unknown generic equipment" do
    account = player_account_fixture()

    assert {:error, :invalid_equipment} =
             Inventory.add_equipment(account.id, "unknown", 1)

    assert Inventory.equipment_count(account.id, "unknown") == 0
  end
end
