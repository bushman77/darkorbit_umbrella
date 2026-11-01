defmodule Darkorbit.ShipStats do
  @moduledoc """
  Persistence boundary for deterministic ship-stat calculations.

  This module loads an owned ship configuration and passes only plain loadout
  data to `Core.Ships.Stats`; no derived values are stored in PostgreSQL.
  """

  import Ecto.Query, warn: false

  alias Core.Ships.Stats
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Loadouts.PlayerShipLoadout
  alias Darkorbit.Repo

  @spec calculate(pos_integer(), pos_integer(), 1 | 2) ::
          {:ok, Stats.t()} | {:error, term()}
  def calculate(user_id, player_ship_id, config_no)
      when is_integer(user_id) and is_integer(player_ship_id) and config_no in [1, 2] do
    query =
      from(loadout in PlayerShipLoadout,
        join: player_ship in PlayerShip,
        on: player_ship.id == loadout.player_ship_id,
        where:
          player_ship.user_id == ^user_id and player_ship.id == ^player_ship_id and
            loadout.config_no == ^config_no,
        select: {player_ship.ship_id, loadout}
      )

    case Repo.one(query) do
      {ship_id, loadout} -> Stats.calculate(ship_id, loadout_data(loadout))
      nil -> {:error, :loadout_not_found}
    end
  end

  def calculate(_user_id, _player_ship_id, _config_no), do: {:error, :invalid_configuration}

  @spec for_active_ship(pos_integer(), 1 | 2) :: {:ok, Stats.t()} | {:error, term()}
  def for_active_ship(user_id, config_no)
      when is_integer(user_id) and config_no in [1, 2] do
    query =
      from(player_ship in PlayerShip,
        join: account in PlayerAccount,
        on: account.id == player_ship.user_id,
        where: player_ship.user_id == ^user_id and player_ship.ship_id == account.ship_id,
        select: player_ship.id
      )

    case Repo.one(query) do
      nil -> {:error, :active_ship_not_found}
      player_ship_id -> calculate(user_id, player_ship_id, config_no)
    end
  end

  def for_active_ship(_user_id, _config_no), do: {:error, :invalid_configuration}

  defp loadout_data(loadout) do
    %{
      lasers: loadout.lasers,
      generators: loadout.generators
    }
  end
end
