defmodule Darkorbit.Piracy.FactionStanding do
  use Ecto.Schema

  schema "solar_faction_standings" do
    field :faction_id, :string
    field :standing, :integer, default: 0
    belongs_to :user, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id
    timestamps(type: :utc_datetime_usec)
  end
end
