defmodule Darkorbit.Fleet.PlayerShip do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_ships" do
    field :ship_id, :integer

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def changeset(player_ship, attrs) do
    player_ship
    |> cast(attrs, [:user_id, :ship_id])
    |> validate_required([:user_id, :ship_id])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :ship_id])
  end
end
