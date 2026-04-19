defmodule Darkorbit.Loadouts.PlayerShipLoadout do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_ship_loadouts" do
    field :config_no, :integer
    field :lasers, :map
    field :generators, :map
    field :drones, :map

    belongs_to :player_ship, Darkorbit.Fleet.PlayerShip

    timestamps()
  end

  @doc false
  def changeset(player_ship_loadout, attrs) do
    player_ship_loadout
    |> cast(attrs, [:player_ship_id, :config_no, :lasers, :generators, :drones])
    |> validate_required([:player_ship_id, :config_no, :lasers, :generators, :drones])
    |> validate_inclusion(:config_no, [1, 2])
    |> foreign_key_constraint(:player_ship_id)
    |> unique_constraint([:player_ship_id, :config_no])
  end
end
