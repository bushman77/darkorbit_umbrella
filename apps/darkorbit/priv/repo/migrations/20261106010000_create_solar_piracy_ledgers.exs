defmodule Darkorbit.Repo.Migrations.CreateSolarPiracyLedgers do
  use Ecto.Migration

  def change do
    create table(:solar_cargo_claims) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :contact_id, :string, null: false
      add :voyage_number, :integer, null: false
      add :encounter_id, :string, null: false
      add :faction_id, :string, null: false
      add :source_manifest, :map, null: false, default: %{}
      add :cargo_units, :map, null: false, default: %{}
      add :strategic_debit, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:solar_cargo_claims, [:contact_id, :voyage_number],
             name: :solar_cargo_claims_vessel_voyage_unique)
    create unique_index(:solar_cargo_claims, [:user_id, :encounter_id],
             name: :solar_cargo_claims_pilot_encounter_unique)

    create table(:solar_faction_standings) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :faction_id, :string, null: false
      add :standing, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:solar_faction_standings, [:user_id, :faction_id])
    create constraint(:solar_faction_standings, :solar_faction_standings_range,
             check: "standing >= -100 AND standing <= 100")

    create table(:solar_faction_events) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :faction_id, :string, null: false
      add :event_key, :string, null: false
      add :kind, :string, null: false
      add :delta, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:solar_faction_events, [:event_key])
    create index(:solar_faction_events, [:user_id, :faction_id])
  end
end
