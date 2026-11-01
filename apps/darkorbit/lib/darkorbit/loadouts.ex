defmodule Darkorbit.Loadouts do
  @moduledoc """
  Two-configuration ship loadouts with atomic inventory transfers.

  Public equipment operations require the acting account id and lock both the
  current loadout and inventory state before applying a mutation.
  """

  import Ecto.Query, warn: false

  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Inventory
  alias Darkorbit.Loadouts.PlayerShipLoadout
  alias Darkorbit.Repo

  @valid_lasers ~w(lf1 lf2 lf3 lf4)
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
    with :ok <- validate_command(user_id, loadout_id, location, slot_index, laser_id) do
      set_laser(user_id, loadout_id, location, slot_index, laser_id)
    end
  end

  @doc """
  Unequips a laser from an owned loadout and returns it to inventory atomically.
  """
  def unequip_laser_to_inventory(user_id, loadout_id, location, slot_index) do
    with :ok <- validate_command(user_id, loadout_id, location, slot_index, nil) do
      set_laser(user_id, loadout_id, location, slot_index, nil)
    end
  end

  defp set_laser(user_id, loadout_id, location, slot_index, new_laser) do
    Repo.transaction(fn ->
      case lock_owned_loadout(user_id, loadout_id) do
        {%PlayerShipLoadout{} = loadout, ship_id} ->
          with {:ok, old_laser, updated_lasers} <-
                 replace_laser(loadout, ship_id, location, slot_index, new_laser),
               :ok <- transfer_lasers(user_id, old_laser, new_laser),
               {:ok, updated_loadout} <-
                 loadout
                 |> PlayerShipLoadout.equipment_changeset(%{"lasers" => updated_lasers})
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

  defp replace_laser(loadout, ship_id, location, slot_index, new_laser) do
    lasers = loadout.lasers || %{}
    slots = Map.get(lasers, location, [])
    usable_slots = ship_caps(ship_id) |> Map.fetch!(location)

    cond do
      slot_index >= length(slots) ->
        {:error, :invalid_slot}

      slot_index >= usable_slots ->
        {:error, :slot_locked}

      true ->
        old_laser = Enum.at(slots, slot_index)
        updated_lasers = Map.put(lasers, location, List.replace_at(slots, slot_index, new_laser))
        {:ok, old_laser, updated_lasers}
    end
  end

  defp transfer_lasers(_user_id, laser, laser), do: :ok

  defp transfer_lasers(user_id, old_laser, new_laser) do
    with :ok <- remove_new_laser(user_id, new_laser),
         :ok <- return_old_laser(user_id, old_laser) do
      :ok
    end
  end

  defp remove_new_laser(_user_id, nil), do: :ok

  defp remove_new_laser(user_id, laser_id) do
    case Inventory.remove_laser(user_id, laser_id, 1) do
      {:ok, _equipment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp return_old_laser(_user_id, nil), do: :ok

  defp return_old_laser(user_id, laser_id) do
    case Inventory.add_lasers(user_id, laser_id, 1) do
      {:ok, _equipment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_command(user_id, loadout_id, location, slot_index, laser_id) do
    cond do
      not is_integer(user_id) or not is_integer(loadout_id) -> {:error, :invalid_owner}
      location not in @locations -> {:error, :invalid_location}
      not is_integer(slot_index) or slot_index < 0 -> {:error, :invalid_slot}
      not is_nil(laser_id) and laser_id not in @valid_lasers -> {:error, :invalid_laser}
      true -> :ok
    end
  end

  defp ship_caps(1), do: %{"ship" => 1, "drones" => 0}
  defp ship_caps(2), do: %{"ship" => 2, "drones" => 0}
  defp ship_caps(3), do: %{"ship" => 3, "drones" => 0}
  defp ship_caps(_ship_id), do: %{"ship" => 1, "drones" => 0}
end
