defmodule Darkorbit.Repo.Migrations.CreatePlayerShips do
  use Ecto.Migration

  def change do
    create table(:player_ships) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :ship_id, :integer, null: false

      timestamps()
    end

    create index(:player_ships, [:user_id])
    create unique_index(:player_ships, [:user_id, :ship_id])
  end
end
