defmodule Darkorbit.Piracy.FactionEvent do
  use Ecto.Schema

  schema "solar_faction_events" do
    field :faction_id, :string
    field :event_key, :string
    field :kind, :string
    field :delta, :integer
    belongs_to :user, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id
    timestamps(type: :utc_datetime_usec)
  end
end
