defmodule Darkorbit.Fleet do
  @moduledoc """
  The Fleet context.
  """

  import Ecto.Query, warn: false

  alias Darkorbit.Repo
  alias Darkorbit.Fleet.PlayerShip
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Loadouts

  def list_player_ships do
    Repo.all(PlayerShip)
  end

  def get_player_ship!(id), do: Repo.get!(PlayerShip, id)

  def list_ships_for_user(user_id) when is_integer(user_id) do
    from(ps in PlayerShip,
      where: ps.user_id == ^user_id,
      order_by: [asc: ps.ship_id]
    )
    |> Repo.all()
  end

  def owned_ship?(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    Repo.get_by(PlayerShip, user_id: user_id, ship_id: ship_id) != nil
  end

  def add_ship_to_user(user_id, ship_id)
      when is_integer(user_id) and is_integer(ship_id) do
    case Repo.get_by(PlayerShip, user_id: user_id, ship_id: ship_id) do
      %PlayerShip{} = player_ship ->
        {:ok, player_ship}

      nil ->
        with {:ok, ship} <-
               %PlayerShip{}
               |> PlayerShip.changeset(%{
                 "user_id" => user_id,
                 "ship_id" => ship_id
               })
               |> Repo.insert(),
             {:ok, _loadouts} <-
               Loadouts.create_default_loadouts_for_player_ship(ship.id) do
          {:ok, ship}
        end
    end
  end

  def create_starter_ships_for_account(user_id) when is_integer(user_id) do
    add_ship_to_user(user_id, 1)
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
end
