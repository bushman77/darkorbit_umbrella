defmodule Darkorbit.PilotLocation.Checkpoint do
  @moduledoc "Durable per-pilot SOL navigation and optional tactical pose."
  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime_usec]

  schema "pilot_location_checkpoints" do
    belongs_to :player, Darkorbit.Accounts.PlayerAccount
    field :navigation, :map, default: %{}
    field :pose_map_id, :string
    field :pose_voyage_number, :integer
    field :pose_ship_instance_id, :integer
    field :pose_position, :map
    field :pose_attitude, :map
    timestamps()
  end
end
