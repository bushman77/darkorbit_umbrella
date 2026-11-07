defmodule Darkorbit.InventoryTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.Inventory

  test "Sunracer starts with an empty four-tonne, server-capacity-limited cargo hold" do
    account = player_account_fixture()
    assert Inventory.cargo_manifest(account.id) == %{}
    assert Inventory.cargo_tonnage(account.id) == 0

    assert {:ok, _} = Inventory.add_cargo(account.id, "titanium", 3)
    assert {:ok, _} = Inventory.add_cargo(account.id, "dilithium", 1)
    assert Inventory.cargo_tonnage(account.id) == 4
    assert Inventory.cargo_manifest(account.id) == %{
      "titanium" => 3, "dilithium" => 1}

    assert {:error, :cargo_hold_full} =
      Inventory.add_cargo(account.id, "methane", 1)
    assert {:error, :not_enough_cargo} =
      Inventory.remove_cargo(account.id, "dilithium", 2)
    assert Inventory.cargo_tonnage(account.id) == 4

    assert {:ok, _} = Inventory.remove_cargo(account.id, "titanium", 2)
    assert Inventory.cargo_tonnage(account.id) == 2
    assert {:ok, _} = Inventory.remove_cargo(account.id, "dilithium", 1)
    assert Inventory.cargo_manifest(account.id) == %{"titanium" => 1}

    assert {:error, :unknown_cargo} =
      Inventory.add_cargo(account.id, "client_defined_priceless_item", 1)
    assert {:error, :invalid_amount} = Inventory.add_cargo(account.id, "titanium", 0)
    assert {:error, :invalid_amount} = Inventory.remove_cargo(account.id, "titanium", -1)
  end

  test "two accounts cannot withdraw cargo from each other's holds" do
    one = player_account_fixture()
    two = player_account_fixture()
    assert {:ok, _} = Inventory.add_cargo(one.id, "salvage", 2)
    assert {:error, :not_enough_cargo} = Inventory.remove_cargo(two.id, "salvage", 1)
    assert Inventory.cargo_manifest(one.id) == %{"salvage" => 2}
    assert Inventory.cargo_manifest(two.id) == %{}
  end

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
