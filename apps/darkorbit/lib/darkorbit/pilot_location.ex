defmodule Darkorbit.PilotLocation do
  @moduledoc """
  PostgreSQL boundary for authoritative pilot navigation and orbital pose.

  Voyage and pose updates touch separate columns to avoid erasing each other.
  No client coordinates are accepted. A saved pose only applies to the same
  physical ship, map, and voyage, never a subsequent visit to the same planet.
  """
  alias Core.Universe.Navigation.Checkpoint, as: VoyageCheckpoint
  alias Core.Universe.OrbitalEntry
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
           is_integer(voyage_number) and voyage_number >= 0 do
    if map_id == OrbitalEntry.map_id(body_id) and valid_pose?(map_id, position, attitude) do
      now = DateTime.utc_now()
      location = xyz(position)
      heading = angles(attitude)
      fields = [
        pose_map_id: map_id, pose_voyage_number: voyage_number,
        pose_ship_instance_id: ship_id,
        pose_position: location, pose_attitude: heading,
        updated_at: now
      ]
      row = %Checkpoint{
        player_id: player_id, navigation: VoyageCheckpoint.dump(navigation),
        pose_map_id: map_id, pose_voyage_number: voyage_number,
        pose_ship_instance_id: ship_id,
        pose_position: location, pose_attitude: heading
      }
      case Repo.insert(row, on_conflict: [set: fields], conflict_target: [:player_id]) do
        {:ok, _} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      :ok
    end
  end
  # During interplanetary transit or isolated tactical combat, do not
  # replace a previous planet's orbital checkpoint.
  def save_pose(_player_id, _map_id, _navigation, _report), do: :ok

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
            if valid_pose?(map_id, position, attitude) do
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

  defp valid_pose?(map_id, %Position{} = position, attitude) do
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
  defp valid_pose?(_, _, _), do: false

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
