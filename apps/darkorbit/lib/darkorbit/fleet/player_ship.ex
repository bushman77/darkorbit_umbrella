defmodule Darkorbit.Fleet.PlayerShip do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_ships" do
    field :ship_id, :integer

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id
    has_many :loadouts, Darkorbit.Loadouts.PlayerShipLoadout

    timestamps()
  end

  @doc false
  def ownership_changeset(player_ship, user_id, ship_id) do
    player_ship
    |> change(user_id: user_id, ship_id: ship_id)
    |> validate_required([:user_id, :ship_id])
    |> validate_number(:ship_id, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :ship_id])
    |> check_constraint(:ship_id, name: :player_ships_ship_id_positive)
  end
end
