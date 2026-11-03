defmodule Darkorbit.Helmets.Device do
  @moduledoc "Persisted, revocable display-only helmet registration."
  use Ecto.Schema
  import Ecto.Changeset

  schema "helmet_devices" do
    belongs_to :player, Darkorbit.Accounts.PlayerAccount
    field :credential_hash, :string
    field :device_name, :string, default: "Phone headset"
    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [:player_id, :credential_hash, :device_name])
    |> validate_required([:player_id, :credential_hash, :device_name])
    |> validate_length(:device_name, min: 1, max: 64)
    |> unique_constraint(:player_id)
    |> unique_constraint(:credential_hash)
    |> foreign_key_constraint(:player_id)
  end
end
