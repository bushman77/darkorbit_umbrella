defmodule Darkorbit.Helmets.Device do
  @moduledoc "Persisted, revocable display-only helmet registration."
  use Ecto.Schema
  import Ecto.Changeset

  schema "helmet_devices" do
    belongs_to :player, Darkorbit.Accounts.PlayerAccount
    field :credential_hash, :string
    field :device_name, :string, default: "Phone headset"
    field :eye_gap_px, :integer
    field :eye_sep_mm, :integer
    timestamps()
  end

  @doc "Validate a complete persisted optical alignment pair."
  def calibration_changeset(device, attrs) do
    device
    |> cast(attrs, [:eye_gap_px, :eye_sep_mm])
    |> validate_required([:eye_gap_px, :eye_sep_mm])
    |> validate_number(:eye_gap_px, greater_than_or_equal_to: -160,
                                  less_than_or_equal_to: 80)
    |> validate_number(:eye_sep_mm, greater_than_or_equal_to: 40,
                                  less_than_or_equal_to: 85)
    |> check_constraint(:eye_gap_px, name: :helmet_eye_gap_range)
    |> check_constraint(:eye_sep_mm, name: :helmet_eye_sep_range)
    |> check_constraint(:eye_gap_px, name: :helmet_calibration_complete)
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
