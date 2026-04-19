defmodule Darkorbit.Titles.PlayerTitle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_titles" do
    field :titles, :map

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def changeset(player_title, attrs) do
    player_title
    |> cast(attrs, [:user_id, :titles])
    |> validate_required([:user_id, :titles])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end
end
