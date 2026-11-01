defmodule Darkorbit.Titles.PlayerTitle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_titles" do
    field :titles, :map

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def creation_changeset(player_title, user_id, attrs) do
    player_title
    |> change(user_id: user_id)
    |> cast(attrs, [:titles])
    |> validate_required([:user_id, :titles])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc false
  def titles_changeset(player_title, attrs) do
    player_title
    |> cast(attrs, [:titles])
    |> validate_required([:titles])
  end
end
