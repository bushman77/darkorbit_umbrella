defmodule Darkorbit.Repo.Migrations.CreatePlayerAccounts do
  use Ecto.Migration

  def change do
    create table(:player_accounts) do
      add :username, :string
      add :email, :string
      add :password_hash, :string
      add :pilot_name, :string
      add :faction_id, :integer
      add :clan_id, :integer
      add :session_id, :string
      add :data, :map
      add :verification, :map
      add :old_pilot_names, :map

      timestamps()
    end
  end
end
