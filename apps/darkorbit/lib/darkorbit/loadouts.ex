defmodule Darkorbit.Loadouts do
  @moduledoc """
  Two-configuration ship loadouts with atomic inventory transfers.

  Public equipment operations require the acting account id and lock both the
  current loadout and inventory state before applying a mutation.
  """

  import Ecto.Query, warn: false

  alias Core.Equipment.Catalog, as: EquipmentCatalog
  alias Core.Equipment.Item
  alias Core.Ships.Catalog, as: ShipCatalog
  alias Core.Ships.Ship
  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts.PlayerShipLoadout
  alias Darkorbit.Repo

  @locations ~w(ship drones)

  def list_player_ship_loadouts, do: Repo.all(PlayerShipLoadout)

  def get_player_ship_loadout!(id), do: Repo.get!(PlayerShipLoadout, id)

  def list_loadouts_for_player_ship(player_ship_id) when is_integer(player_ship_id) do
    from(loadout in PlayerShipLoadout,
      where: loadout.player_ship_id == ^player_ship_id,
      order_by: [asc: loadout.config_no]
    )
    |> Repo.all()
  end

  def get_loadout(player_ship_id, config_no)
      when is_integer(player_ship_id) and config_no in [1, 2] do
    Repo.get_by(PlayerShipLoadout,
      player_ship_id: player_ship_id,
      config_no: config_no
    )
  end

  def create_default_loadout(player_ship_id, config_no)
      when is_integer(player_ship_id) and config_no in [1, 2] do
    attrs = %{
      config_no: config_no,
      lasers: %{
        "ship" => List.duplicate(nil, 15),
        "drones" => List.duplicate(nil, 16)
      },
      generators: %{
        "ship" => List.duplicate(nil, 15),
        "drones" => List.duplicate(nil, 16)
      },
      drones: %{
        "formation" => nil,
        "slots" => List.duplicate(nil, 8)
      }
    }

    %PlayerShipLoadout{}
    |> PlayerShipLoadout.creation_changeset(player_ship_id, attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:player_ship_id, :config_no],
      returning: true
    )
    |> case do
      {:ok, %PlayerShipLoadout{id: nil}} ->
        {:ok,
         Repo.get_by!(PlayerShipLoadout,
           player_ship_id: player_ship_id,
           config_no: config_no
         )}

      result ->
        result
    end
  end

  def create_default_loadouts_for_player_ship(player_ship_id) when is_integer(player_ship_id) do
    with {:ok, _configuration_one} <- create_default_loadout(player_ship_id, 1),
         {:ok, _configuration_two} <- create_default_loadout(player_ship_id, 2) do
      {:ok, list_loadouts_for_player_ship(player_ship_id)}
    end
  end

  @doc """
  Equips one owned laser into an owned loadout and returns any replaced laser
  to inventory in the same transaction.
  """
  def equip_laser_from_inventory(user_id, loadout_id, location, slot_index, laser_id) do
    with :ok <- validate_command(user_id, loadout_id, location, slot_index, laser_id, :lasers) do
      set_equipment(user_id, loadout_id, location, slot_index, laser_id, :lasers)
    end
  end

  @doc """
  Unequips a laser from an owned loadout and returns it to inventory atomically.
  """
  def unequip_laser_to_inventory(user_id, loadout_id, location, slot_index) do
    with :ok <- validate_command(user_id, loadout_id, location, slot_index, nil, :lasers) do
      set_equipment(user_id, loadout_id, location, slot_index, nil, :lasers)
    end
  end

  @doc """
  Equips either a speed generator or shield into a generator slot.
  """
  def equip_generator_from_inventory(
        user_id,
        loadout_id,
        location,
        slot_index,
        equipment_id
      ) do
    with :ok <-
           validate_command(
             user_id,
             loadout_id,
             location,
             slot_index,
             equipment_id,
             :generators
           ) do
      set_equipment(user_id, loadout_id, location, slot_index, equipment_id, :generators)
    end
  end

  @doc """
  Unequips a speed generator or shield and returns it to inventory atomically.
  """
  def unequip_generator_to_inventory(user_id, loadout_id, location, slot_index) do
    with :ok <- validate_command(user_id, loadout_id, location, slot_index, nil, :generators) do
      set_equipment(user_id, loadout_id, location, slot_index, nil, :generators)
    end
  end

  defp set_equipment(user_id, loadout_id, location, slot_index, new_item, field) do
    Repo.transaction(fn ->
      case lock_owned_loadout(user_id, loadout_id) do
        {%PlayerShipLoadout{} = loadout, ship_id} ->
          with {:ok, old_item, updated_slots} <-
                 replace_equipment(loadout, ship_id, location, slot_index, new_item, field),
               :ok <- transfer_equipment(user_id, old_item, new_item, field),
               {:ok, updated_loadout} <-
                 loadout
                 |> PlayerShipLoadout.equipment_changeset(%{
                   Atom.to_string(field) => updated_slots
                 })
                 |> Repo.update() do
            updated_loadout
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          Repo.rollback(:loadout_not_found)
      end
    end)
  end

  defp lock_owned_loadout(user_id, loadout_id) do
    from(loadout in PlayerShipLoadout,
      join: player_ship in PlayerShip,
      on: player_ship.id == loadout.player_ship_id,
      where: loadout.id == ^loadout_id and player_ship.user_id == ^user_id,
      select: {loadout, player_ship.ship_id},
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp replace_equipment(loadout, ship_id, location, slot_index, new_item, field) do
    with {:ok, ship} <- fetch_ship(ship_id) do
      equipment = loadout_equipment(loadout, field)
      slots = Map.get(equipment, location, [])
      usable_slots = slot_capacity(ship, field, location)

      cond do
        slot_index >= length(slots) ->
          {:error, :invalid_slot}

        slot_index >= usable_slots ->
          {:error, :slot_locked}

        true ->
          old_item = Enum.at(slots, slot_index)

          updated_equipment =
            Map.put(equipment, location, List.replace_at(slots, slot_index, new_item))

          {:ok, old_item, updated_equipment}
      end
    end
  end

  defp transfer_equipment(_user_id, item, item, _field), do: :ok

  defp transfer_equipment(user_id, old_item, new_item, field) do
    with :ok <- remove_new_equipment(user_id, new_item, field),
         :ok <- return_old_equipment(user_id, old_item, field) do
      :ok
    end
  end

  defp remove_new_equipment(_user_id, nil, _field), do: :ok

  defp remove_new_equipment(user_id, item_id, field) do
    case inventory_remove(user_id, item_id, field) do
      {:ok, _equipment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp return_old_equipment(_user_id, nil, _field), do: :ok

  defp return_old_equipment(user_id, item_id, field) do
    case inventory_add(user_id, item_id, field) do
      {:ok, _equipment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_command(user_id, loadout_id, location, slot_index, item_id, field) do
    cond do
      not is_integer(user_id) or not is_integer(loadout_id) -> {:error, :invalid_owner}
      location not in @locations -> {:error, :invalid_location}
      not is_integer(slot_index) or slot_index < 0 -> {:error, :invalid_slot}
      not compatible_equipment?(item_id, field) -> invalid_equipment_error(field)
      true -> :ok
    end
  end

  defp compatible_equipment?(nil, _field), do: true

  defp compatible_equipment?(item_id, field) when is_binary(item_id) do
    case EquipmentCatalog.fetch(item_id) do
      {:ok, %Item{category: :laser}} ->
        field == :lasers

      {:ok, %Item{category: category}} when category in [:generator, :shield] ->
        field == :generators

      _other ->
        false
    end
  end

  defp compatible_equipment?(_item_id, _field), do: false

  defp invalid_equipment_error(:lasers), do: {:error, :invalid_laser}
  defp invalid_equipment_error(:generators), do: {:error, :invalid_generator}

  defp fetch_ship(ship_id) do
    case ShipCatalog.fetch(ship_id) do
      {:ok, ship} -> {:ok, ship}
      :error -> {:error, :unknown_ship}
    end
  end

  defp loadout_equipment(loadout, :lasers), do: loadout.lasers || %{}
  defp loadout_equipment(loadout, :generators), do: loadout.generators || %{}

  defp slot_capacity(%Ship{laser_slots: slots}, :lasers, "ship"), do: slots
  defp slot_capacity(%Ship{generator_slots: slots}, :generators, "ship"), do: slots
  defp slot_capacity(%Ship{}, _field, "drones"), do: 0

  defp inventory_remove(user_id, item_id, :lasers),
    do: Inventory.remove_laser(user_id, item_id, 1)

  defp inventory_remove(user_id, item_id, :generators),
    do: Inventory.remove_equipment(user_id, item_id, 1)

  defp inventory_add(user_id, item_id, :lasers), do: Inventory.add_lasers(user_id, item_id, 1)

  defp inventory_add(user_id, item_id, :generators),
    do: Inventory.add_equipment(user_id, item_id, 1)
end
