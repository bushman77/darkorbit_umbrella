defmodule Darkorbit.Inventory do
  @moduledoc """
  Server-authoritative player inventory operations.

  Every stack mutation locks the owning inventory row for the duration of its
  database transaction, preventing lost updates and duplicated equipment.
  """

  import Ecto.Query, warn: false

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Core.Ships.Catalog, as: ShipCatalog
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Cargo.Catalog, as: CargoCatalog
  alias Core.Equipment.Item
  alias Darkorbit.Inventory.PlayerEquipment
  alias Darkorbit.Repo

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
        "cargo" => %{},
        "equipment" => %{
          "lasers" => %{"lf1" => 0, "lf2" => 0, "lf3" => 0, "lf4" => 0},
          "generators" => %{},
          "shields" => %{},
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

  def equipment_count(user_id, item_id) when is_integer(user_id) and is_binary(item_id) do
    with {:ok, item} <- EquipmentCatalog.fetch(item_id),
         %PlayerEquipment{} = equipment <- get_equipment_by_user_id(user_id) do
      equipment_count_from_items(equipment.items, item)
    else
      _not_found -> 0
    end
  end

  def equipment_count(_user_id, _item_id), do: 0

  def add_equipment(user_id, item_id, amount)
      when is_integer(user_id) and is_binary(item_id) and is_integer(amount) and amount > 0 do
    with {:ok, item} <- fetch_equipment(item_id) do
      mutate_equipment(user_id, item, fn current -> {:ok, current + amount} end)
    end
  end

  def add_equipment(_user_id, item_id, _amount) when is_binary(item_id) do
    case EquipmentCatalog.fetch(item_id) do
      :error -> {:error, :invalid_equipment}
      {:ok, _item} -> {:error, :invalid_amount}
    end
  end

  def add_equipment(_user_id, _item_id, _amount), do: {:error, :invalid_amount}

  def remove_equipment(user_id, item_id, amount)
      when is_integer(user_id) and is_binary(item_id) and is_integer(amount) and amount > 0 do
    with {:ok, item} <- fetch_equipment(item_id) do
      mutate_equipment(user_id, item, fn current ->
        if current >= amount,
          do: {:ok, current - amount},
          else: {:error, :not_enough_equipment}
      end)
    end
  end

  def remove_equipment(_user_id, item_id, _amount) when is_binary(item_id) do
    case EquipmentCatalog.fetch(item_id) do
      :error -> {:error, :invalid_equipment}
      {:ok, _item} -> {:error, :invalid_amount}
    end
  end

  def remove_equipment(_user_id, _item_id, _amount), do: {:error, :invalid_amount}

  @doc "Persisted cargo hold quantities; never accept a client-supplied mass."
  def cargo_manifest(user_id) when is_integer(user_id) do
    case get_equipment_by_user_id(user_id) do
      %PlayerEquipment{items: items} ->
        Map.get(items || %{}, "cargo", %{})

      nil ->
        %{}
    end
  end

  def cargo_manifest(_user_id), do: %{}

  @spec cargo_tonnage(pos_integer()) :: non_neg_integer()
  def cargo_tonnage(user_id) when is_integer(user_id) do
    user_id |> cargo_manifest() |> cargo_tonnage_from_manifest()
  end

  def cargo_tonnage(_user_id), do: 0

  @doc """
  Atomically load cargo into the account's active ship, with an account lock,
  inventory row lock, fixed catalog mass and server-owned capacity.
  """
  def add_cargo(user_id, cargo_id, amount)
      when is_integer(user_id) and user_id > 0 and is_integer(amount) and amount > 0 do
    with {:ok, item} <- CargoCatalog.fetch(cargo_id) do
      Repo.transaction(fn ->
        account =
          from(account in PlayerAccount,
            where: account.id == ^user_id, lock: "FOR UPDATE")
          |> Repo.one()

        equipment =
          from(equipment in PlayerEquipment,
            where: equipment.user_id == ^user_id, lock: "FOR UPDATE")
          |> Repo.one()

        with %PlayerAccount{} <- account,
             %PlayerEquipment{} <- equipment,
             {:ok, ship} <- ShipCatalog.fetch(account.ship_id),
             manifest <- Map.get(equipment.items || %{}, "cargo", %{}),
             used <- cargo_tonnage_from_manifest(manifest),
             true <- used + amount * item.mass_tonnes <= ship.cargo_capacity do
          updated = Map.update(manifest, cargo_id, amount, &(&1 + amount))
          save_cargo!(equipment, updated)
        else
          nil -> Repo.rollback(:cargo_hold_unavailable)
          {:error, _} -> Repo.rollback(:unknown_ship)
          false -> Repo.rollback(:cargo_hold_full)
          _ -> Repo.rollback(:cargo_hold_unavailable)
        end
      end)
    end
  end

  def add_cargo(_user_id, cargo_id, _amount) do
    case CargoCatalog.fetch(cargo_id) do
      {:error, _} = error -> error
      {:ok, _} -> {:error, :invalid_amount}
    end
  end

  @doc "Unloads only quantities the server confirms are present."
  def remove_cargo(user_id, cargo_id, amount)
      when is_integer(user_id) and user_id > 0 and is_integer(amount) and amount > 0 do
    with {:ok, _item} <- CargoCatalog.fetch(cargo_id) do
      Repo.transaction(fn ->
        equipment =
          from(equipment in PlayerEquipment,
            where: equipment.user_id == ^user_id, lock: "FOR UPDATE")
          |> Repo.one()

        case equipment do
          %PlayerEquipment{} = row ->
            manifest = Map.get(row.items || %{}, "cargo", %{})
            count = Map.get(manifest, cargo_id, 0)

            if count < amount do
              Repo.rollback(:not_enough_cargo)
            else
              left = count - amount
              updated = if left == 0,
                do: Map.delete(manifest, cargo_id),
                else: Map.put(manifest, cargo_id, left)
              save_cargo!(row, updated)
            end

          nil ->
            Repo.rollback(:cargo_hold_unavailable)
        end
      end)
    end
  end

  def remove_cargo(_user_id, cargo_id, _amount) do
    case CargoCatalog.fetch(cargo_id) do
      {:error, _} = error -> error
      {:ok, _} -> {:error, :invalid_amount}
    end
  end

  defp cargo_tonnage_from_manifest(manifest) do
    Enum.reduce(manifest, 0, fn {id, amount}, total ->
      case CargoCatalog.fetch(id) do
        {:ok, item} when is_integer(amount) and amount >= 0 ->
          total + amount * item.mass_tonnes
        _ ->
          total
      end
    end)
  end

  defp save_cargo!(row, cargo) do
    updated_items = Map.put(row.items || %{}, "cargo", cargo)
    case row |> PlayerEquipment.items_changeset(updated_items) |> Repo.update() do
      {:ok, saved} -> saved
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def laser_count(user_id, laser_id) do
    if equipment_in_category?(laser_id, :laser),
      do: equipment_count(user_id, laser_id),
      else: 0
  end

  def add_lasers(user_id, laser_id, amount) do
    if equipment_in_category?(laser_id, :laser) do
      add_equipment(user_id, laser_id, amount)
    else
      {:error, :invalid_laser}
    end
  end

  def remove_laser(user_id, laser_id, amount) do
    if equipment_in_category?(laser_id, :laser) do
      case remove_equipment(user_id, laser_id, amount) do
        {:error, :not_enough_equipment} -> {:error, :not_enough_lasers}
        result -> result
      end
    else
      {:error, :invalid_laser}
    end
  end

  defp mutate_equipment(user_id, item, operation) do
    Repo.transaction(fn ->
      equipment =
        from(equipment in PlayerEquipment,
          where: equipment.user_id == ^user_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case equipment do
        %PlayerEquipment{} = equipment ->
          current = equipment_count_from_items(equipment.items, item)

          case operation.(current) do
            {:ok, new_count} -> persist_equipment_count(equipment, item, new_count)
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          Repo.rollback(:equipment_not_found)
      end
    end)
  end

  defp persist_equipment_count(equipment, item, new_count) do
    items = equipment.items || %{}
    equipment_bag = Map.get(items, "equipment", %{})
    bucket_name = EquipmentCatalog.inventory_bucket(item)
    bucket = Map.get(equipment_bag, bucket_name, %{})

    new_bucket =
      if new_count == 0,
        do: Map.delete(bucket, item.id),
        else: Map.put(bucket, item.id, new_count)

    new_items =
      Map.put(items, "equipment", Map.put(equipment_bag, bucket_name, new_bucket))

    equipment
    |> PlayerEquipment.items_changeset(new_items)
    |> Repo.update()
    |> case do
      {:ok, updated_equipment} -> updated_equipment
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp equipment_count_from_items(items, item) do
    count =
      (items || %{})
      |> Map.get("equipment", %{})
      |> Map.get(EquipmentCatalog.inventory_bucket(item), %{})
      |> Map.get(item.id, 0)

    if is_integer(count) and count >= 0, do: count, else: 0
  end

  defp fetch_equipment(item_id) do
    case EquipmentCatalog.fetch(item_id) do
      {:ok, item} -> {:ok, item}
      :error -> {:error, :invalid_equipment}
    end
  end

  defp equipment_in_category?(item_id, category) when is_binary(item_id) do
    case EquipmentCatalog.fetch(item_id) do
      {:ok, %Item{category: ^category}} -> true
      _other -> false
    end
  end

  defp equipment_in_category?(_item_id, _category), do: false

  defp inserted_or_existing({:ok, %PlayerEquipment{id: nil}}, user_id) do
    {:ok, Repo.get_by!(PlayerEquipment, user_id: user_id)}
  end

  defp inserted_or_existing(result, _user_id), do: result
end
