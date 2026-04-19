defmodule Darkorbit.Preferences.PlayerSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_settings" do
    field :settings, :map

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def changeset(player_setting, attrs) do
    player_setting
    |> cast(attrs, [:user_id, :settings])
    |> validate_required([:user_id, :settings])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end
end
