defmodule Darkorbit.Preferences.PlayerSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_settings" do
    field :settings, :map

    belongs_to :player_account, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id

    timestamps()
  end

  @doc false
  def creation_changeset(player_setting, user_id, attrs) do
    player_setting
    |> change(user_id: user_id)
    |> cast(attrs, [:settings])
    |> validate_required([:user_id, :settings])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc false
  def settings_changeset(player_setting, attrs) do
    player_setting
    |> cast(attrs, [:settings])
    |> validate_required([:settings])
  end
end
