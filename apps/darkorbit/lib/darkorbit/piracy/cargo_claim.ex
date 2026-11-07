defmodule Darkorbit.Piracy.CargoClaim do
  use Ecto.Schema

  schema "solar_cargo_claims" do
    field :contact_id, :string
    field :voyage_number, :integer
    field :encounter_id, :string
    field :faction_id, :string
    field :source_manifest, :map, default: %{}
    field :cargo_units, :map, default: %{}
    field :strategic_debit, :map, default: %{}
    belongs_to :user, Darkorbit.Accounts.PlayerAccount, foreign_key: :user_id
    timestamps(type: :utc_datetime_usec)
  end
end
