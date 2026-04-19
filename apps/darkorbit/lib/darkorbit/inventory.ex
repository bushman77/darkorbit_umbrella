defmodule Darkorbit.Inventory do
  @moduledoc """
  The Inventory context.
  """

  import Ecto.Query, warn: false
  alias Darkorbit.Repo

  alias Darkorbit.Inventory.PlayerEquipment
  alias Darkorbit.Accounts.PlayerAccount

  def list_player_equipment do
    Repo.all(PlayerEquipment)
  end

  def get_player_equipment!(id), do: Repo.get!(PlayerEquipment, id)

  def get_equipment_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerEquipment, user_id: user_id)
  end

  def create_default_equipment_for_account(user_id) when is_integer(user_id) do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        {:ok, equipment}

      nil ->
        items = %{
          "apis" => false,
          "zeus" => false,
          "equipment" => %{
            "lasers" => %{
              "lf1" => 0,
              "lf2" => 0,
              "lf3" => 0,
              "lf4" => 0
            },
            "generators" => %{},
            "drones" => %{}
          },
          "skill_tree" => %{
            "logdisks" => 0,
            "research_points" => 0,
            "reset_count" => 0
          }
        }

        skill_points = %{
          "engineering" => 0,
          "shieldEngineering" => 0,
          "detonation1" => 0,
          "detonation2" => 0,
          "heatseekingMissiles" => 0,
          "rocketFusion" => 0,
          "cruelty1" => 0,
          "cruelty2" => 0,
          "explosives" => 0,
          "luck1" => 0,
          "luck2" => 0
        }

        %PlayerEquipment{}
        |> PlayerEquipment.changeset(%{
          "user_id" => user_id,
          "items" => items,
          "skill_points" => skill_points
        })
        |> Repo.insert()
    end
  end

  def owned_ship?(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        ship_ids = Map.get(equipment.items || %{}, "ships", [])
        ship_id in ship_ids

      nil ->
        false
    end
  end

  def add_ship_to_account(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        items = equipment.items || %{}
        ship_ids = Map.get(items, "ships", [])

        if ship_id in ship_ids do
          {:ok, equipment}
        else
          new_items =
            Map.put(items, "ships", Enum.sort([ship_id | ship_ids]))

          equipment
          |> PlayerEquipment.changeset(%{"items" => new_items})
          |> Repo.update()
        end

      nil ->
        {:error, :equipment_not_found}
    end
  end

  def change_active_ship(%PlayerAccount{} = account, ship_id)
      when is_integer(ship_id) do
    cond do
      not owned_ship?(account.id, ship_id) ->
        {:error, :ship_not_owned}

      account.ship_id == ship_id ->
        {:ok, account}

      true ->
        account
        |> PlayerAccount.changeset(%{"ship_id" => ship_id})
        |> Repo.update()
    end
  end

  def laser_count(user_id, laser_id)
      when is_integer(user_id) and is_binary(laser_id) do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        equipment.items
        |> Map.get("equipment", %{})
        |> Map.get("lasers", %{})
        |> Map.get(laser_id, 0)

      nil ->
        0
    end
  end

  def add_lasers(user_id, laser_id, amount)
      when is_integer(user_id) and is_binary(laser_id) and is_integer(amount) and amount > 0 do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        items = equipment.items || %{}
        equipment_bag = Map.get(items, "equipment", %{})
        lasers = Map.get(equipment_bag, "lasers", %{})

        new_count = Map.get(lasers, laser_id, 0) + amount

        new_lasers =
          lasers
          |> Map.put(laser_id, new_count)

        new_equipment_bag =
          equipment_bag
          |> Map.put("lasers", new_lasers)

        new_items =
          items
          |> Map.put("equipment", new_equipment_bag)

        equipment
        |> PlayerEquipment.changeset(%{"items" => new_items})
        |> Repo.update()

      nil ->
        {:error, :equipment_not_found}
    end
  end

  def remove_laser(user_id, laser_id, amount)
      when is_integer(user_id) and is_binary(laser_id) and is_integer(amount) and amount > 0 do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment ->
        items = equipment.items || %{}
        equipment_bag = Map.get(items, "equipment", %{})
        lasers = Map.get(equipment_bag, "lasers", %{})

        current = Map.get(lasers, laser_id, 0)

        cond do
          current < amount ->
            {:error, :not_enough_lasers}

          true ->
            new_lasers =
              case current - amount do
                0 -> Map.delete(lasers, laser_id)
                new_count -> Map.put(lasers, laser_id, new_count)
              end

            new_equipment_bag =
              equipment_bag
              |> Map.put("lasers", new_lasers)

            new_items =
              items
              |> Map.put("equipment", new_equipment_bag)

            equipment
            |> PlayerEquipment.changeset(%{"items" => new_items})
            |> Repo.update()
        end

      nil ->
        {:error, :equipment_not_found}
    end
  end
end
