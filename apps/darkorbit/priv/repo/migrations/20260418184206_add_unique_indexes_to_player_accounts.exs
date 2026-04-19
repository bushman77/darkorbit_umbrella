defmodule Darkorbit.Repo.Migrations.AddUniqueIndexesToPlayerAccounts do
  use Ecto.Migration

  def change do
    create unique_index(:player_accounts, [:username])
    create unique_index(:player_accounts, [:email])
    create unique_index(:player_accounts, [:pilot_name])
    create unique_index(:player_accounts, [:session_id])
  end
end
