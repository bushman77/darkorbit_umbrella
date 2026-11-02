defmodule Core.Combat.LineOfFire do
  @moduledoc """
  Server-owned manual laser ray against living NPC collision spheres.

  Direction comes from the authoritative ship attitude, never a claimed
  client target or ray. A miss remains a shot and consumes weapon cooldown.
  """
  alias Core.Combat

  # NPC octahedrons render at radius ~2 world-scaled scene units (0.06),
  # so 40 world units gives a little aiming tolerance from the cockpit.
  @npc_radius 40.0

  @spec trace(map(), map(), [map()], number()) ::
          {:hit, map(), map()} | {:miss, map()}
  def trace(origin, direction, npcs, max_distance)
      when is_list(npcs) and is_number(max_distance) and max_distance > 0 do
    hit =
      npcs
      |> Enum.filter(&Combat.alive?/1)
      |> Enum.flat_map(fn npc ->
        case ray_sphere(origin, direction, npc.position, @npc_radius, max_distance) do
          nil -> []
          distance -> [{distance, to_string(npc.id), npc}]
        end
      end)
      |> Enum.sort_by(fn {distance, id, _npc} -> {distance, id} end)
      |> List.first()

    case hit do
      {distance, _id, npc} -> {:hit, npc, extend(origin, direction, distance)}
      nil -> {:miss, extend(origin, direction, max_distance)}
    end
  end

  defp ray_sphere(origin, direction, center, radius, max_distance) do
    offset = %{
      x: center.x - origin.x,
      y: center.y - origin.y,
      z: center.z - origin.z
    }

    projection = dot(offset, direction)
    center_distance_sq = dot(offset, offset)

    # Preserve the weapon's center-to-center range limit, matching the
    # existing Combat.validate_attack/3 contract for actual damage.
    if projection < 0 or center_distance_sq > max_distance * max_distance do
      nil
    else
      perpendicular_sq = max(0.0, center_distance_sq - projection * projection)

      if perpendicular_sq > radius * radius do
        nil
      else
        distance = max(0.0, projection - :math.sqrt(radius * radius - perpendicular_sq))
        if distance <= max_distance, do: distance, else: nil
      end
    end
  end

  defp extend(p, d, distance),
    do: %{x: p.x + d.x * distance, y: p.y + d.y * distance,
          z: p.z + d.z * distance}

  defp dot(a, b), do: a.x * b.x + a.y * b.y + a.z * b.z
end
