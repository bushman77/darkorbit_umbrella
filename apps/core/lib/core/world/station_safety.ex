defmodule Core.World.StationSafety do
  @moduledoc """
  Server-owned refinery proximity and impact handling in real orbital km.

  The cockpit's projected long-distance station mesh is *not* collision
  geometry. Collision uses only the map's immutable OrbitalEntry station pose
  and a conservative bounding sphere, swept between consecutive ship positions
  so a fast pilot cannot tunnel through it. Unlike planetary contact, station
  impact stops flight and applies bounded, speed-dependent combat damage.

  Berth admission is deliberately not inferred from proximity. Until a later
  authenticated docking protocol supplies approach corridors, the station
  body is a protected solid exclusion volume.
  """

  alias Core.Combat
  alias Core.Universe.OrbitalEntry
  alias Core.World.{Entity, MapDefinition, PlanetaryCollision, Position}

  @caution_radius_km 2_500.0
  @critical_radius_km 1_200.0
  @separation_km 0.25
  @zero_vector %{x: 0.0, y: 0.0, z: 0.0}
  @zero_rotation %{yaw: 0.0, pitch: 0.0, roll: 0.0}

  @spec warning(Position.t(), MapDefinition.t()) :: map() | nil
  def warning(_position, %MapDefinition{planet: nil}), do: nil

  def warning(%Position{} = position, %MapDefinition{planet: %{body_id: body_id}}) do
    case OrbitalEntry.space_base(body_id) do
      %{position_3d: center, collision_radius_km: radius} = station ->
        distance = distance(position, center)

        level =
          cond do
            distance <= @critical_radius_km -> :critical
            distance <= @caution_radius_km -> :caution
            true -> :clear
          end

        if level == :clear do
          nil
        else
          %{
            station_id: station.id,
            level: level,
            clearance_km: max(0.0, distance - radius),
            collision_radius_km: radius,
            distance_km: distance
          }
        end

      _ -> nil
    end
  end

  @spec transition(term(), map() | nil, map() | nil, non_neg_integer()) ::
          map() | nil
  def transition(entity_id, previous, current, tick) do
    before = if(previous, do: previous.level, else: :clear)
    after_level = if(current, do: current.level, else: :clear)

    if before == after_level do
      nil
    else
      %{
        entity_id: entity_id,
        station_id: (current || previous).station_id,
        previous_level: before,
        level: after_level,
        clearance_km: if(current, do: current.clearance_km, else: nil),
        tick: tick
      }
    end
  end

  @spec resolve(Entity.t(), Entity.t(), MapDefinition.t(), number()) ::
          {:ok, Entity.t()} | {:impact, Entity.t(), map()}
  def resolve(%Entity{} = _before, %Entity{} = moved,
              %MapDefinition{planet: nil}, _elapsed_seconds), do: {:ok, moved}

  def resolve(%Entity{} = _before, %Entity{status: :destroyed} = moved,
              %MapDefinition{}, _elapsed_seconds), do: {:ok, moved}

  def resolve(%Entity{} = before, %Entity{} = moved,
              %MapDefinition{planet: %{body_id: body_id}}, elapsed_seconds)
      when is_number(elapsed_seconds) and elapsed_seconds > 0 do
    case OrbitalEntry.space_base(body_id) do
      %{position_3d: center, collision_radius_km: radius} = station ->
        case PlanetaryCollision.first_contact(before.position, moved.position, center, radius) do
          :clear -> {:ok, moved}

          {:hit, contact} ->
            # Resolve just outside the station's immutable hull, even if an
            # invalid saved ship position was already inside the station.
            position = separated(contact, before.position, center, radius)
            speed = distance(before.position, moved.position) / elapsed_seconds
            damage = if speed <= 0.0, do: 0, else: min(100, max(1, ceil(speed / 10.0)))
            {damaged, report} = Combat.apply_damage(moved, damage)

            stopped = %{damaged |
              position: position,
              destination: nil,
              route_waypoints: [],
              navigation_mode: :manual,
              throttle: 0.0,
              cruise_speed: 0.0,
              velocity: @zero_vector,
              rotation_input: @zero_rotation,
              angular_velocity: @zero_rotation
            }

            {:impact, stopped, %{
              station_id: station.id,
              entity_id: before.id,
              tick_speed_km_s: speed,
              damage: report
            }}
        end

      _ -> {:ok, moved}
    end
  end

  defp distance(a, b) do
    dx = a.x - b.x
    dy = a.y - b.y
    dz = a.z - b.z
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  defp separated(contact, before, center, radius) do
    dx = contact.x - center.x
    dy = contact.y - center.y
    dz = contact.z - center.z
    length = :math.sqrt(dx * dx + dy * dy + dz * dz)

    {nx, ny, nz} =
      if length > 1.0e-9 do
        {dx / length, dy / length, dz / length}
      else
        bx = before.x - center.x
        by = before.y - center.y
        bz = before.z - center.z
        old_length = :math.sqrt(bx * bx + by * by + bz * bz)
        if old_length > 1.0e-9,
          do: {bx / old_length, by / old_length, bz / old_length},
          else: {1.0, 0.0, 0.0}
      end

    %Position{x: center.x + nx * (radius + @separation_km),
              y: center.y + ny * (radius + @separation_km),
              z: center.z + nz * (radius + @separation_km)}
  end
end
