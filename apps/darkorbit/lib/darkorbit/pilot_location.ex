defmodule Darkorbit.PilotLocation do
  @moduledoc """
  PostgreSQL boundary for authoritative pilot navigation and orbital pose.

  Voyage and pose updates touch separate columns to avoid erasing each other.
  No client coordinates are accepted. A saved pose only applies to the same
  physical ship, map, and voyage, never a subsequent visit to the same planet.
  """
  alias Core.Universe.Navigation.Checkpoint, as: VoyageCheckpoint
  alias Core.Universe.{FreeFlightRegion, OrbitalEntry}
  alias Core.World.{Movement, PlanetaryCollision, Position, StationSafety}
  alias Darkorbit.PilotLocation.Checkpoint
  alias Darkorbit.Repo

  def load_navigation(player_id) when is_integer(player_id) and player_id > 0 do
    case Repo.get_by(Checkpoint, player_id: player_id) do
      nil -> nil
      row -> row.navigation
    end
  end

  def save_navigation(player_id, data)
      when is_integer(player_id) and player_id > 0 and is_map(data) do
    with {:ok, _} <- VoyageCheckpoint.load(data) do
      now = DateTime.utc_now()
      case Repo.insert(%Checkpoint{player_id: player_id, navigation: data},
             on_conflict: [set: [navigation: data, updated_at: now]],
             conflict_target: [:player_id]) do
        {:ok, _} -> :ok
        {:error, error} -> {:error, error}
      end
    end
  end

  def save_pose(player_id, map_id,
                %{status: :idle, location_id: body_id,
                  voyage_number: voyage_number} = navigation,
                %{ship_instance_id: ship_id, position: position, attitude: attitude})
      when is_integer(player_id) and player_id > 0 and
           is_integer(ship_id) and ship_id > 0 and
           is_integer(voyage_number) and voyage_number >= 0 and is_binary(body_id) do
    if map_id == OrbitalEntry.map_id(body_id) and
         valid_pose?(player_id, map_id, position, attitude) do
      save_pose_row(player_id, map_id, navigation, voyage_number, ship_id,
        position, attitude)
    else
      :ok
    end
  end
  # A suspended conventional cockpit in free space has a local pose too.
  # Its authoritative SOL position is stored independently in navigation.
  def save_pose(player_id, map_id,
                %{status: status, location_id: location_id, free_flight: free_flight,
                  voyage_number: voyage_number, tactical_encounter: nil} = navigation,
                %{ship_instance_id: ship_id, position: position, attitude: attitude})
      when is_integer(player_id) and player_id > 0 and
           is_integer(ship_id) and ship_id > 0 and
           is_integer(voyage_number) and voyage_number >= 0 and
           ((status == :traveling and free_flight == true) or
              (status == :idle and is_nil(location_id))) do
    if map_id == FreeFlightRegion.map_id(player_id) and
         valid_pose?(player_id, map_id, position, attitude) do
      save_pose_row(player_id, map_id, navigation, voyage_number, ship_id,
        position, attitude)
    else
      :ok
    end
  end

  # In automated cruise there is no conventional ship pose to retain.
  # An ongoing tactical encounter must be settled first.
  def save_pose(_player_id, _map_id, _navigation, _report), do: :ok

  defp save_pose_row(player_id, map_id, navigation, voyage_number, ship_id,
         position, attitude) do
    now = DateTime.utc_now()
    location = xyz(position)
    heading = angles(attitude)
    fields = [
      pose_map_id: map_id, pose_voyage_number: voyage_number,
      pose_ship_instance_id: ship_id, pose_position: location,
      pose_attitude: heading, updated_at: now
    ]
    record = %Checkpoint{player_id: player_id,
      navigation: VoyageCheckpoint.dump(navigation), pose_map_id: map_id,
      pose_voyage_number: voyage_number, pose_ship_instance_id: ship_id,
      pose_position: location, pose_attitude: heading}
    case Repo.insert(record, on_conflict: [set: fields],
           conflict_target: [:player_id]) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def restore_entry(player_id, ship_id, %{map_id: "sol:" <> _} = entry, voyage_number)
      when is_integer(player_id) and player_id > 0 and
           is_integer(ship_id) and ship_id > 0 and is_integer(voyage_number) do
    case Repo.get_by(Checkpoint, player_id: player_id) do
      %Checkpoint{
        pose_map_id: map_id, pose_voyage_number: ^voyage_number,
        pose_ship_instance_id: ^ship_id,
        pose_position: position, pose_attitude: attitude
      } when map_id == entry.map_id ->
        case parse_pose(position, attitude) do
          {:ok, position, attitude} ->
            if valid_pose?(player_id, map_id, position, attitude) do
              %{entry | position: position, attitude: attitude}
            else
              entry
            end
          :error -> entry
        end
      _ -> entry
    end
  end
  def restore_entry(_player_id, _ship_id, entry, _voyage), do: entry

  defp valid_pose?(player_id, map_id, %Position{} = position, attitude)
       when map_id == "sol:free_" <> Integer.to_string(player_id) do
    # The private SOL cockpit has no planetary collision sphere. Validate
    # against its exact server-owned 3D boundaries, including altitude.
    match?({:ok, _},
      Movement.destination(FreeFlightRegion.definition(player_id), position)) and
      valid_angles?(attitude)
  end

  defp valid_pose?(_player_id, map_id, %Position{} = position, attitude) do
    case Enum.find(OrbitalEntry.planet_maps(), &(&1.id == map_id)) do
      %{planet: planet} = map ->
        match?({:ok, _}, Movement.destination(map, position)) and
          valid_angles?(attitude) and
          PlanetaryCollision.first_contact(position, position, planet.center,
            planet.exclusion_radius) == :clear and
          not inside_station?(position, map)
      _ -> false
    end
  end
  defp valid_pose?(_, _, _, _), do: false

  defp inside_station?(position, map) do
    case StationSafety.warning(position, map) do
      %{clearance_km: clearance} when clearance <= 0 -> true
      _ -> false
    end
  end

  defp valid_angles?(%{yaw: yaw, pitch: pitch, roll: roll}) do
    Enum.all?([yaw, pitch, roll], fn a -> finite?(a) and abs(a) < 10 end)
  end
  defp valid_angles?(_), do: false
  defp finite?(n) when is_number(n), do: n == n and abs(n) < 1.0e12
  defp finite?(_), do: false

  defp xyz(%Position{x: x, y: y, z: z}), do: %{"x" => x, "y" => y, "z" => z}
  defp angles(%{yaw: yaw, pitch: pitch, roll: roll}),
    do: %{"yaw" => yaw, "pitch" => pitch, "roll" => roll}

  defp parse_pose(%{"x" => x, "y" => y, "z" => z},
                  %{"yaw" => yaw, "pitch" => pitch, "roll" => roll}) do
    if Enum.all?([x, y, z, yaw, pitch, roll], &finite?/1) do
      {:ok, %Position{x: x, y: y, z: z},
       %{yaw: yaw, pitch: pitch, roll: roll}}
    else
      :error
    end
  end
  defp parse_pose(_, _), do: :error
end
