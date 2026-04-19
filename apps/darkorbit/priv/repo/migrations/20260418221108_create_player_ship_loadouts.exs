defmodule Darkorbit.Repo.Migrations.CreatePlayerShipLoadouts do
  use Ecto.Migration

  def change do
    create table(:player_ship_loadouts) do
      add :player_ship_id, references(:player_ships, on_delete: :delete_all), null: false
      add :config_no, :integer, null: false
      add :lasers, :map, null: false, default: %{}
      add :generators, :map, null: false, default: %{}
      add :drones, :map, null: false, default: %{}

      timestamps()
    end

    create index(:player_ship_loadouts, [:player_ship_id])
    create unique_index(:player_ship_loadouts, [:player_ship_id, :config_no])
  end
end
