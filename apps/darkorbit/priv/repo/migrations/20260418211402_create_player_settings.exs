defmodule Darkorbit.Repo.Migrations.CreatePlayerSettings do
  use Ecto.Migration

  def change do
    create table(:player_settings) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :settings, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:player_settings, [:user_id])
  end
end
