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
  def creation_changeset(player_equipment, user_id, attrs) do
    player_equipment
    |> change(user_id: user_id)
    |> cast(attrs, [:items, :skill_points])
    |> validate_required([:user_id, :items, :skill_points])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc false
  def items_changeset(player_equipment, items) when is_map(items) do
    player_equipment
    |> change(items: items)
    |> validate_required([:items])
  end
end
