defmodule Core.Combat.LineOfFire do
  @moduledoc """
  Server-owned manual laser ray against living NPC collision spheres.

  Direction comes from the authoritative ship attitude, never a claimed
  client target or ray. A miss remains a shot and consumes weapon cooldown.
  """
  alias Core.Combat
  alias Core.World.Orientation

  # Geometry is in the same scaled units as the 3D cockpit. These are two
  # independent emitters attached to the ship, NOT client-side offsets.
  # A wing lies 1.75 scene units either side of the nose, behind each
  # forward-facing muzzle. Camera local origin is (0, 2.75, 0).
  @scene_scale 0.06
  @muzzle_forward_scene 3.2
  @muzzle_up_scene 1.3
  @wing_half_span_scene 1.75
  @wings [:left, :right]

  # NPC octahedrons are rendered with radius 2 scene units (33 world
  # units); a 40-unit collision sphere allows both wing rays to hit an
  # enemy centered on the crosshair without invisible target snapping.
  @npc_radius 40.0

  @doc "Absolute server-owned XYZ positions for symmetric, rotating gun mounts."
  @spec wing_muzzles(map(), Orientation.t()) :: [map()]
  def wing_muzzles(position, orientation) do
    Enum.map(@wings, fn side ->
      offset = %{
        x: (if side == :left, do: -1.0, else: 1.0) * @wing_half_span_scene,
        y: @muzzle_up_scene,
        z: -@muzzle_forward_scene
      }

      scene = Orientation.rotate(orientation, offset)
      %{
        side: side,
        from: %{
          x: position.x + scene.x / @scene_scale,
          y: position.y + scene.z / @scene_scale,
          z: Map.get(position, :z, 0.0) + scene.y / @scene_scale
        }
      }
    end)
  end

  @doc """
  Trace both parallel nose-aimed wing lasers against the same world state.
  Returns two beams (hit or miss). No lock-on, client ray or damage required.
  """
  @spec trace_pair(map(), Orientation.t(), [map()], number()) :: [map()]
  def trace_pair(position, orientation, npcs, max_distance)
      when is_list(npcs) and is_number(max_distance) and max_distance > 0 do
    heading = Orientation.forward(orientation)
    # Muzzle already extends forward from ship center. Keep the physical
    # maximum range measured from the player, not from the new muzzle.
    remaining = max(0.01, max_distance - @muzzle_forward_scene / @scene_scale)
    eligible =
      Enum.filter(npcs, fn npc ->
        Combat.alive?(npc) and Map.get(npc, :state) != :surrendered and
          Combat.in_range?(%{position: position}, npc, max_distance)
      end)

    Enum.map(wing_muzzles(position, orientation), fn %{side: side, from: origin} ->
      case trace(origin, heading, eligible, remaining) do
        {:hit, target, impact} ->
          %{side: side, from: origin, to: impact, target: target,
            target_id: target.id, hit: true}

        {:miss, endpoint} ->
          %{side: side, from: origin, to: endpoint, target: nil,
            target_id: nil, hit: false}
      end
    end)
  end

  @doc "Server-approved pair of lock-on beams, drawn towards one actual NPC."
  def locked_pair(position, orientation, npc_position) do
    to = %{x: npc_position.x, y: npc_position.y,
           z: Map.get(npc_position, :z, 0.0)}
    Enum.map(wing_muzzles(position, orientation), fn %{side: side, from: origin} ->
      %{side: side, from: origin, to: to, hit: true}
    end)
  end

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
