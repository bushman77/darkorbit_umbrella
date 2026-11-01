defmodule Darkorbit.Fleet do
  @moduledoc """
  Authoritative ship ownership and active-ship operations.

  Adding a ship and provisioning both of its configurations is one atomic,
  idempotent operation.
  """

  import Ecto.Query, warn: false

  alias Core.Ships.Catalog, as: ShipCatalog
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Loadouts
  alias Darkorbit.Repo

  def list_player_ships, do: Repo.all(PlayerShip)

  def get_player_ship!(id), do: Repo.get!(PlayerShip, id)

  def list_ships_for_user(user_id) when is_integer(user_id) do
    from(player_ship in PlayerShip,
      where: player_ship.user_id == ^user_id,
      order_by: [asc: player_ship.ship_id]
    )
    |> Repo.all()
  end

  def get_active_ship(user_id) when is_integer(user_id) do
    query =
      from(player_ship in PlayerShip,
        join: account in PlayerAccount,
        on: account.id == player_ship.user_id,
        where: player_ship.user_id == ^user_id and player_ship.ship_id == account.ship_id
      )

    case Repo.one(query) do
      %PlayerShip{} = player_ship -> {:ok, player_ship}
      nil -> {:error, :active_ship_not_found}
    end
  end

  def owned_ship?(user_id, ship_id) when is_integer(user_id) and is_integer(ship_id) do
    Repo.exists?(
      from(player_ship in PlayerShip,
        where: player_ship.user_id == ^user_id and player_ship.ship_id == ^ship_id
      )
    )
  end

  def add_ship_to_user(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) and ship_id > 0 do
    case ShipCatalog.fetch(ship_id) do
      {:ok, _ship} -> do_add_ship_to_user(user_id, ship_id)
      :error -> {:error, :unknown_ship}
    end
  end

  def add_ship_to_user(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    do_add_ship_to_user(user_id, ship_id)
  end

  defp do_add_ship_to_user(user_id, ship_id) do
    Repo.transaction(fn ->
      with {:ok, player_ship} <- insert_or_get_ship(user_id, ship_id),
           {:ok, _loadouts} <-
             Loadouts.create_default_loadouts_for_player_ship(player_ship.id) do
        player_ship
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_starter_ships_for_account(user_id) when is_integer(user_id) do
    add_ship_to_user(user_id, 1)
  end

  def change_active_ship(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    Repo.transaction(fn ->
      account =
        from(account in PlayerAccount, where: account.id == ^user_id, lock: "FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(account) ->
          Repo.rollback(:account_not_found)

        not owned_ship?(user_id, ship_id) ->
          Repo.rollback(:ship_not_owned)

        account.ship_id == ship_id ->
          account

        true ->
          account
          |> PlayerAccount.system_changeset(%{"ship_id" => ship_id})
          |> Repo.update()
          |> case do
            {:ok, updated_account} -> updated_account
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  defp insert_or_get_ship(user_id, ship_id) do
    %PlayerShip{}
    |> PlayerShip.ownership_changeset(user_id, ship_id)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :ship_id],
      returning: true
    )
    |> case do
      {:ok, %PlayerShip{id: nil}} ->
        {:ok, Repo.get_by!(PlayerShip, user_id: user_id, ship_id: ship_id)}

      result ->
        result
    end
  end
end
