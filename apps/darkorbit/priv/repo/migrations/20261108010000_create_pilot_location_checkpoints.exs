defmodule Darkorbit.Repo.Migrations.CreatePilotLocationCheckpoints do
  use Ecto.Migration

  def change do
    create table(:pilot_location_checkpoints) do
      add :player_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :navigation, :map, null: false, default: %{}
      add :pose_map_id, :string
      add :pose_voyage_number, :integer
      add :pose_ship_instance_id, :bigint
      add :pose_position, :map
      add :pose_attitude, :map
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:pilot_location_checkpoints, [:player_id])
    create constraint(:pilot_location_checkpoints, :pilot_location_pose_voyage_valid,
      check: "pose_voyage_number IS NULL OR pose_voyage_number >= 0")
  end
end
