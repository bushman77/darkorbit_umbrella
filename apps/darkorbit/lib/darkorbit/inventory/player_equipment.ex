defmodule Darkorbit.Inventory.PlayerEquipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_equipment" do
    field :items, :map
    field :skill_points, :map

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def changeset(player_equipment, attrs) do
    player_equipment
    |> cast(attrs, [:user_id, :items, :skill_points])
    |> validate_required([:user_id, :items, :skill_points])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end
end
