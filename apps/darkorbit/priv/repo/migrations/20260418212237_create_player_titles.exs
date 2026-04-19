defmodule Darkorbit.Repo.Migrations.CreatePlayerTitles do
  use Ecto.Migration

  def change do
    create table(:player_titles) do
      add :user_id, references(:player_accounts, on_delete: :delete_all), null: false
      add :titles, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:player_titles, [:user_id])
  end
end
