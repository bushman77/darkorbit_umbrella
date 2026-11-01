defmodule Darkorbit.Inventory do
  @moduledoc """
  Server-authoritative player inventory operations.

  Every stack mutation locks the owning inventory row for the duration of its
  database transaction, preventing lost updates and duplicated equipment.
  """

  import Ecto.Query, warn: false

  alias Darkorbit.Inventory.PlayerEquipment
  alias Darkorbit.Repo

  @valid_lasers ~w(lf1 lf2 lf3 lf4)

  def list_player_equipment, do: Repo.all(PlayerEquipment)

  def get_player_equipment!(id), do: Repo.get!(PlayerEquipment, id)

  def get_equipment_by_user_id(user_id) when is_integer(user_id) do
    Repo.get_by(PlayerEquipment, user_id: user_id)
  end

  def create_default_equipment_for_account(user_id) when is_integer(user_id) do
    attrs = %{
      items: %{
        "apis" => false,
        "zeus" => false,
        "equipment" => %{
          "lasers" => %{"lf1" => 0, "lf2" => 0, "lf3" => 0, "lf4" => 0},
          "generators" => %{},
          "drones" => %{}
        },
        "skill_tree" => %{
          "logdisks" => 0,
          "research_points" => 0,
          "reset_count" => 0
        }
      },
      skill_points: %{
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
    }

    %PlayerEquipment{}
    |> PlayerEquipment.creation_changeset(user_id, attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id], returning: true)
    |> inserted_or_existing(user_id)
  end

  def laser_count(user_id, laser_id)
      when is_integer(user_id) and laser_id in @valid_lasers do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{} = equipment -> laser_count_from_items(equipment.items, laser_id)
      nil -> 0
    end
  end

  def laser_count(_user_id, _laser_id), do: 0

  def add_lasers(user_id, laser_id, amount)
      when is_integer(user_id) and laser_id in @valid_lasers and is_integer(amount) and
             amount > 0 do
    mutate_lasers(user_id, laser_id, fn current -> {:ok, current + amount} end)
  end

  def add_lasers(_user_id, laser_id, _amount) when laser_id not in @valid_lasers,
    do: {:error, :invalid_laser}

  def add_lasers(_user_id, _laser_id, _amount), do: {:error, :invalid_amount}

  def remove_laser(user_id, laser_id, amount)
      when is_integer(user_id) and laser_id in @valid_lasers and is_integer(amount) and
             amount > 0 do
    mutate_lasers(user_id, laser_id, fn current ->
      if current >= amount,
        do: {:ok, current - amount},
        else: {:error, :not_enough_lasers}
    end)
  end

  def remove_laser(_user_id, laser_id, _amount) when laser_id not in @valid_lasers,
    do: {:error, :invalid_laser}

  def remove_laser(_user_id, _laser_id, _amount), do: {:error, :invalid_amount}

  defp mutate_lasers(user_id, laser_id, operation) do
    Repo.transaction(fn ->
      equipment =
        from(equipment in PlayerEquipment,
          where: equipment.user_id == ^user_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case equipment do
        %PlayerEquipment{} = equipment ->
          current = laser_count_from_items(equipment.items, laser_id)

          case operation.(current) do
            {:ok, new_count} -> persist_laser_count(equipment, laser_id, new_count)
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          Repo.rollback(:equipment_not_found)
      end
    end)
  end

  defp persist_laser_count(equipment, laser_id, new_count) do
    items = equipment.items || %{}
    equipment_bag = Map.get(items, "equipment", %{})
    lasers = Map.get(equipment_bag, "lasers", %{})

    new_lasers =
      if new_count == 0,
        do: Map.delete(lasers, laser_id),
        else: Map.put(lasers, laser_id, new_count)

    new_items =
      Map.put(items, "equipment", Map.put(equipment_bag, "lasers", new_lasers))

    equipment
    |> PlayerEquipment.items_changeset(new_items)
    |> Repo.update()
    |> case do
      {:ok, updated_equipment} -> updated_equipment
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp laser_count_from_items(items, laser_id) do
    count =
      (items || %{})
      |> Map.get("equipment", %{})
      |> Map.get("lasers", %{})
      |> Map.get(laser_id, 0)

    if is_integer(count) and count >= 0, do: count, else: 0
  end

  defp inserted_or_existing({:ok, %PlayerEquipment{id: nil}}, user_id) do
    {:ok, Repo.get_by!(PlayerEquipment, user_id: user_id)}
  end

  defp inserted_or_existing(result, _user_id), do: result
end
