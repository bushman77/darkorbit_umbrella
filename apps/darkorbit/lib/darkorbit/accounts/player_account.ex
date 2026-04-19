defmodule Darkorbit.Accounts.PlayerAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_accounts" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :pilot_name, :string
    field :faction_id, :integer
    field :clan_id, :integer
    field :session_id, :string
    field :data, :map
    field :verification, :map
    field :old_pilot_names, :map
    field :ship_id, :integer
    field :rank_id, :integer
    field :experience, :integer
    field :honor, :integer
    field :credits, :integer
    field :uridium, :integer
    field :level, :integer
    field :version, :string
    timestamps()
  end

  @doc false
  def changeset(player_account, attrs) do
    player_account
    |> cast(attrs, [
      :username,
      :email,
      :password_hash,
      :pilot_name,
      :faction_id,
      :clan_id,
      :session_id,
      :data,
      :verification,
      :old_pilot_names,
      :ship_id,
      :rank_id,
      :experience,
      :honor,
      :credits,
      :uridium,
      :level,
      :version
    ])
    |> validate_required([
      :username,
      :email,
      :password_hash,
      :pilot_name,
      :faction_id,
      :clan_id,
      :session_id,
      :data,
      :verification,
      :old_pilot_names
    ])
    |> validate_length(:username, min: 4, max: 20)
    |> validate_length(:pilot_name, min: 4, max: 20)
    |> validate_length(:email, max: 260)
    |> validate_format(:username, ~r/^[A-Za-z0-9_.]+$/)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> unique_constraint(:pilot_name)
    |> unique_constraint(:session_id)
  end
end
