defmodule Darkorbit.Repo.Migrations.CreatePlayerShipConditions do
  use Ecto.Migration

  def change do
    create table(:player_ship_conditions) do
      add :player_ship_id, references(:player_ships, on_delete: :delete_all), null: false
      add :hull, :integer, null: false
      add :max_hull, :integer, null: false
      add :shields, :integer, null: false
      add :max_shields, :integer, null: false
      add :status, :string, null: false, default: "alive"
      add :revision, :bigint, null: false, default: 0

      timestamps()
    end

    create unique_index(:player_ship_conditions, [:player_ship_id])

    create constraint(:player_ship_conditions, :player_ship_conditions_valid_values,
             check: "max_hull > 0 AND hull >= 0 AND hull <= max_hull AND max_shields >= 0 AND shields >= 0 AND shields <= max_shields"
           )

    create constraint(:player_ship_conditions, :player_ship_conditions_valid_status,
             check: "(status = 'destroyed' AND hull = 0) OR (status IN ('alive', 'surrendered') AND hull > 0)"
           )
  end
end
