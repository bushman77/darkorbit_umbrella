defmodule Darkorbit.Repo.Migrations.AddLegacyFieldsToPlayerAccounts do
  use Ecto.Migration

  def change do
    alter table(:player_accounts) do
      add :ship_id, :integer, default: 1
      add :rank_id, :integer, default: 1
      add :experience, :bigint, default: 0
      add :honor, :bigint, default: 0
      add :credits, :bigint, default: 0
      add :uridium, :bigint, default: 0
      add :level, :integer, default: 1
      add :version, :string, default: "live"
    end
  end
end
