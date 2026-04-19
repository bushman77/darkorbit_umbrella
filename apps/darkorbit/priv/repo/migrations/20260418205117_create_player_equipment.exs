defmodule Darkorbit.Repo.Migrations.CreatePlayerEquipment do
  use Ecto.Migration

  def change do
    create table(:player_equipment) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :items, :map, null: false, default: %{}
      add :skill_points, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:player_equipment, [:user_id])
  end
end
