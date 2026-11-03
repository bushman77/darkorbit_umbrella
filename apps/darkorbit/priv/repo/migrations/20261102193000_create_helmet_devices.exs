defmodule Darkorbit.Repo.Migrations.CreateHelmetDevices do
  use Ecto.Migration

  def change do
    create table(:helmet_devices) do
      add :player_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :credential_hash, :string, null: false
      add :device_name, :string, null: false, default: "Phone headset"

      timestamps()
    end

    create unique_index(:helmet_devices, [:player_id])
    create unique_index(:helmet_devices, [:credential_hash])
  end
end
