defmodule Darkorbit.Loadouts do
  @moduledoc """
  The Loadouts context.
  """

  import Ecto.Query, warn: false

  alias Darkorbit.Repo
  alias Darkorbit.Loadouts.PlayerShipLoadout
  alias Darkorbit.Fleet.PlayerShip

  @valid_lasers ["lf1", "lf2", "lf3", "lf4"]

  def list_player_ship_loadouts do
    Repo.all(PlayerShipLoadout)
  end

  def get_player_ship_loadout!(id), do: Repo.get!(PlayerShipLoadout, id)

  def list_loadouts_for_player_ship(player_ship_id) when is_integer(player_ship_id) do
    from(psl in PlayerShipLoadout,
      where: psl.player_ship_id == ^player_ship_id,
      order_by: [asc: psl.config_no]
    )
    |> Repo.all()
  end

  def get_loadout(player_ship_id, config_no)
      when is_integer(player_ship_id) and config_no in [1, 2] do
    Repo.get_by(PlayerShipLoadout, player_ship_id: player_ship_id, config_no: config_no)
  end

  def create_default_loadout(player_ship_id, config_no)
      when is_integer(player_ship_id) and config_no in [1, 2] do
    case get_loadout(player_ship_id, config_no) do
      %PlayerShipLoadout{} = loadout ->
        {:ok, loadout}

      nil ->
        %PlayerShipLoadout{}
        |> PlayerShipLoadout.changeset(%{
          "player_ship_id" => player_ship_id,
          "config_no" => config_no,
          "lasers" => %{
            "ship" => List.duplicate(nil, 15),
            "drones" => List.duplicate(nil, 16)
          },
          "generators" => %{
            "ship" => List.duplicate(nil, 15),
            "drones" => List.duplicate(nil, 16)
          },
          "drones" => %{
            "formation" => nil,
            "slots" => List.duplicate(nil, 8)
          }
        })
        |> Repo.insert()
    end
  end

  def create_default_loadouts_for_player_ship(player_ship_id) when is_integer(player_ship_id) do
    with {:ok, _cfg1} <- create_default_loadout(player_ship_id, 1),
         {:ok, _cfg2} <- create_default_loadout(player_ship_id, 2) do
      {:ok, list_loadouts_for_player_ship(player_ship_id)}
    end
  end

  def update_player_ship_loadout(%PlayerShipLoadout{} = player_ship_loadout, attrs) do
    player_ship_loadout
    |> PlayerShipLoadout.changeset(attrs)
    |> Repo.update()
  end

  def equip_laser(%PlayerShipLoadout{} = loadout, location, slot_index, laser_id)
      when location in ["ship", "drones"] and is_integer(slot_index) do
    lasers = loadout.lasers || %{}
    slots = Map.get(lasers, location, [])
    usable_slots = usable_laser_slots(loadout, location)

    cond do
      slot_index < 0 or slot_index >= length(slots) ->
        {:error, :invalid_slot}

      slot_index >= usable_slots ->
        {:error, :slot_locked}

      not is_nil(laser_id) and laser_id not in @valid_lasers ->
        {:error, :invalid_laser}

      true ->
        updated_slots = List.replace_at(slots, slot_index, laser_id)

        updated_lasers =
          lasers
          |> Map.put(location, updated_slots)

        update_player_ship_loadout(loadout, %{"lasers" => updated_lasers})
    end
  end

  def equip_laser_from_inventory(%PlayerShipLoadout{} = loadout, location, slot_index, laser_id)
      when location in ["ship", "drones"] and is_integer(slot_index) and is_binary(laser_id) do
    alias Ecto.Multi
    alias Darkorbit.Inventory

    lasers = loadout.lasers || %{}
    slots = Map.get(lasers, location, [])
    existing = Enum.at(slots, slot_index)

    with %PlayerShip{user_id: user_id} <- Repo.get(PlayerShip, loadout.player_ship_id) do
      Multi.new()
      |> Multi.run(:remove_laser, fn _repo, _changes ->
        Inventory.remove_laser(user_id, laser_id, 1)
      end)
      |> maybe_return_old_laser(existing, user_id)
      |> Multi.run(:equip_laser, fn _repo, _changes ->
        equip_laser(loadout, location, slot_index, laser_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{equip_laser: updated_loadout}} ->
          {:ok, updated_loadout}

        {:error, :remove_laser, reason, _changes_so_far} ->
          {:error, reason}

        {:error, :return_old_laser, reason, _changes_so_far} ->
          {:error, reason}

        {:error, :equip_laser, reason, _changes_so_far} ->
          {:error, reason}
      end
    else
      nil -> {:error, :player_ship_not_found}
    end
  end

  defp maybe_return_old_laser(multi, nil, _user_id), do: multi

  defp maybe_return_old_laser(multi, old_laser, user_id) do
    Ecto.Multi.run(multi, :return_old_laser, fn _repo, _changes ->
      Darkorbit.Inventory.add_lasers(user_id, old_laser, 1)
    end)
  end

  defp usable_laser_slots(%PlayerShipLoadout{} = loadout, location) do
    case Repo.get(PlayerShip, loadout.player_ship_id) do
      %PlayerShip{ship_id: ship_id} ->
        caps = ship_caps(ship_id)
        Map.fetch!(caps, location)

      nil ->
        0
    end
  end

  defp ship_caps(1), do: %{"ship" => 1, "drones" => 0}
  defp ship_caps(2), do: %{"ship" => 2, "drones" => 0}
  defp ship_caps(3), do: %{"ship" => 3, "drones" => 0}
  defp ship_caps(_), do: %{"ship" => 1, "drones" => 0}
end
