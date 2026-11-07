defmodule Darkorbit.Fleet.PlayerShipCondition do
  @moduledoc "Durable combat condition for one owned physical player ship."

  use Ecto.Schema

  schema "player_ship_conditions" do
    belongs_to :player_ship, Darkorbit.Fleet.PlayerShip

    field :hull, :integer
    field :max_hull, :integer
    field :shields, :integer
    field :max_shields, :integer
    field :status, Ecto.Enum, values: [:alive, :surrendered, :destroyed]
    field :revision, :integer, default: 0

    timestamps()
  end
end
