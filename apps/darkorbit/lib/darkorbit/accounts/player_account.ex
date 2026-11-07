defmodule Darkorbit.Accounts.PlayerAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_accounts" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true, redact: true
    field :verification_token, :string, virtual: true, redact: true
    field :pilot_name, :string
    field :faction_id, :integer, default: 0
    field :clan_id, :integer, default: 0
    field :session_id, :string
    field :data, :map, default: %{}
    field :verification, :map, default: %{}
    field :old_pilot_names, :map, default: %{"history" => []}
    field :ship_id, :integer, default: 1
    field :rank_id, :integer, default: 1
    field :experience, :integer, default: 0
    field :honor, :integer, default: 0
    field :credits, :integer, default: 0
    field :uridium, :integer, default: 0
    field :level, :integer, default: 1
    field :version, :string, default: "live"

    has_many :player_ships, Darkorbit.Fleet.PlayerShip, foreign_key: :user_id
    has_one :player_equipment, Darkorbit.Inventory.PlayerEquipment, foreign_key: :user_id
    has_one :player_setting, Darkorbit.Preferences.PlayerSetting, foreign_key: :user_id
    has_one :player_title, Darkorbit.Titles.PlayerTitle, foreign_key: :user_id

    timestamps()
  end

  @registration_fields [:username, :email, :pilot_name, :password]
  @server_fields [
    :password_hash,
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
  ]

  @doc """
  Builds a registration changeset from player-controlled identity fields.

  Currency, progression, faction, ship, verification, and session values come
  from the server-owned struct and cannot be overridden by registration input.
  """
  def registration_changeset(player_account, attrs) do
    player_account
    |> cast(attrs, @registration_fields)
    |> update_change(:email, fn email ->
      email |> String.trim() |> String.downcase()
    end)
    |> validate_required(@registration_fields)
    |> validate_length(:username, min: 4, max: 20)
    |> validate_length(:pilot_name, min: 4, max: 20)
    |> validate_length(:email, max: 260)
    |> validate_format(:username, ~r/^[A-Za-z0-9_.]+$/)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_password_byte_length()
    |> put_password_hash()
    |> validate_required(@server_fields)
    |> common_constraints()
  end

  @doc false
  def system_changeset(player_account, attrs) do
    player_account
    |> cast(attrs, [:session_id, :verification, :faction_id, :ship_id, :data])
    |> validate_required([:session_id, :verification, :faction_id, :ship_id])
    |> common_constraints()
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true} = changeset) do
    case get_change(changeset, :password) do
      password when is_binary(password) ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      _other ->
        changeset
    end
  end

  defp put_password_hash(changeset), do: changeset

  defp common_constraints(changeset) do
    changeset
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> unique_constraint(:pilot_name)
    |> unique_constraint(:session_id)
    |> check_constraint(:faction_id, name: :player_accounts_faction_id_range)
    |> check_constraint(:credits, name: :player_accounts_credits_non_negative)
    |> check_constraint(:uridium, name: :player_accounts_uridium_non_negative)
    |> check_constraint(:experience, name: :player_accounts_experience_non_negative)
    |> check_constraint(:level, name: :player_accounts_level_positive)
    |> check_constraint(:ship_id, name: :player_accounts_ship_id_positive)
    |> check_constraint(:rank_id, name: :player_accounts_rank_id_positive)
  end

  defp validate_password_byte_length(changeset) do
    validate_change(changeset, :password, fn :password, password ->
      if byte_size(password) <= 72,
        do: [],
        else: [password: "should be at most 72 bytes"]
    end)
  end
end
