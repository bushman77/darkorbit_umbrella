defmodule Darkorbit.InventoryTest do
  use Darkorbit.DataCase

  alias Darkorbit.Inventory

  describe "player_equipment" do
    alias Darkorbit.Inventory.PlayerEquipment

    import Darkorbit.InventoryFixtures

    @invalid_attrs %{items: nil, skill_points: nil}

    test "list_player_equipment/0 returns all player_equipment" do
      player_equipment = player_equipment_fixture()
      assert Inventory.list_player_equipment() == [player_equipment]
    end

    test "get_player_equipment!/1 returns the player_equipment with given id" do
      player_equipment = player_equipment_fixture()
      assert Inventory.get_player_equipment!(player_equipment.id) == player_equipment
    end

    test "create_player_equipment/1 with valid data creates a player_equipment" do
      valid_attrs = %{items: %{}, skill_points: %{}}

      assert {:ok, %PlayerEquipment{} = player_equipment} = Inventory.create_player_equipment(valid_attrs)
      assert player_equipment.items == %{}
      assert player_equipment.skill_points == %{}
    end

    test "create_player_equipment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_player_equipment(@invalid_attrs)
    end

    test "update_player_equipment/2 with valid data updates the player_equipment" do
      player_equipment = player_equipment_fixture()
      update_attrs = %{items: %{}, skill_points: %{}}

      assert {:ok, %PlayerEquipment{} = player_equipment} = Inventory.update_player_equipment(player_equipment, update_attrs)
      assert player_equipment.items == %{}
      assert player_equipment.skill_points == %{}
    end

    test "update_player_equipment/2 with invalid data returns error changeset" do
      player_equipment = player_equipment_fixture()
      assert {:error, %Ecto.Changeset{}} = Inventory.update_player_equipment(player_equipment, @invalid_attrs)
      assert player_equipment == Inventory.get_player_equipment!(player_equipment.id)
    end

    test "delete_player_equipment/1 deletes the player_equipment" do
      player_equipment = player_equipment_fixture()
      assert {:ok, %PlayerEquipment{}} = Inventory.delete_player_equipment(player_equipment)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_player_equipment!(player_equipment.id) end
    end

    test "change_player_equipment/1 returns a player_equipment changeset" do
      player_equipment = player_equipment_fixture()
      assert %Ecto.Changeset{} = Inventory.change_player_equipment(player_equipment)
    end
  end
end
