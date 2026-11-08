defmodule Core.World.GreenStarbaseSafety do
  @moduledoc """
  Stage-3 server-authoritative swept collision and proximity for the independent
  Green Starbase. Only active in the pilot's own SOL free-flight region when
  Navigation confirms the idle voyage is at the starbase waypoint.

  Hull pieces mirror the flat-shaded Three.js model at WORLD_SCALE 0.06:
  two square pyramids, left/right supports and braces, top/bottom framing,
  hangar floor and a solid rear wall. The FRONT aperture is deliberately
  absent from the collision volume. This permits a future supervised docking
  approach but does not authorize docking or remove the player entity.

  Geometry is evaluated in station-relative *scene* units for exact alignment
  with the model, then converted to immutable server-owned world kilometres.
  No mesh raycasts, client-controlled station coordinates or extra sockets.
  """

  alias Core.Combat
  alias Core.Universe.GreenStarbase
  alias Core.World.{Entity, Position}

  @scale 0.06
  @collision_separation_scene 0.03
  @caution_km 3_000.0
  @critical_km 1_500.0
  @outer_hull_km 1_100.0
  @zero_vector %{x: 0.0, y: 0.0, z: 0.0}
  @zero_rotation %{yaw: 0.0, pitch: 0.0, roll: 0.0}

  # Each piece is specified in Three.js local XYZ. The camera transform maps
  # world XY to scene XZ, and world altitude Z to scene Y.
  @boxes [
    {:left_support, {-28.0, 0.0, 0.0}, {6.0, 10.0, 24.0}},
    {:right_support, {28.0, 0.0, 0.0}, {6.0, 10.0, 24.0}},
    {:left_brace, {-36.0, 0.0, 0.0}, {3.5, 11.5, 26.5}},
    {:right_brace, {36.0, 0.0, 0.0}, {3.5, 11.5, 26.5}},
    {:roof, {0.0, 12.0, 0.0}, {22.0, 2.0, 24.0}},
    {:lower_beam, {0.0, -12.0, 0.0}, {22.0, 2.0, 24.0}},
    {:hangar_floor, {0.0, -9.0, 0.0}, {22.0, 1.0, 22.5}},
    {:hangar_rear_wall, {0.0, 0.0, 23.5}, {22.0, 9.0, 0.5}}
  ]

  @doc "True when a world-kilometre position lies inside one of the solids."
  def inside?(%Position{} = position) do
    local = scene_position(position)
    Enum.any?(pieces(), fn {_name, planes} -> inside_planes?(local, planes) end)
  end

  @doc "Approach guidance uses the open front aperture, not a solid sphere."
  def open_approach?(%Position{} = position) do
    {x, y, z} = scene_position(position)
    abs(x) < 18.0 and y > -7.5 and y < 8.0 and z < 23.0
  end

  @doc "Read-only warning. Activated by the server's SOL Navigation state."
  def warning(%Position{} = position, true) do
    {x, y, z} = scene_position(position)
    distance_km = :math.sqrt(x*x + y*y + z*z) / @scale
    level =
      cond do
        distance_km > @caution_km -> :clear
        distance_km <= @critical_km and open_approach?(position) -> :approach
        distance_km <= @critical_km -> :critical
        true -> :caution
      end

    if level == :clear, do: nil, else: %{
      station_id: GreenStarbase.id(),
      station_kind: :starbase,
      level: level,
      distance_km: distance_km,
      clearance_km: max(0.0, distance_km - @outer_hull_km),
      collision_radius_km: @outer_hull_km,
      docking_available: false
    }
  end
  def warning(%Position{}, _inactive), do: nil

  @doc """
  First hit against the compound station hull, including a segment that
  traverses the entire building within one server tick. The open front
  corridor is clear; the back wall stops a ship that has not docked.
  """
  def first_contact(%Position{} = from, %Position{} = to) do
    start = scene_position(from)
    finish = scene_position(to)
    hits =
      Enum.flat_map(pieces(), fn {name, planes} ->
        case clip_segment(start, finish, planes) do
          nil -> []
          {fraction, point} -> [{fraction, name, world_position(point)}]
        end
      end)

    case Enum.min_by(hits, fn {fraction, _, _} -> fraction end, fn -> nil end) do
      nil -> :clear
      {fraction, part, position} -> {:hit, %{t: fraction, part: part, position: position}}
    end
  end

  def resolve(%Entity{} = _before, %Entity{} = moved, false, _elapsed), do: {:ok, moved}
  def resolve(%Entity{} = _before, %Entity{status: :destroyed} = moved, _active, _elapsed),
    do: {:ok, moved}

  def resolve(%Entity{} = before, %Entity{} = moved, true, dt)
      when is_number(dt) and dt > 0 do
    case first_contact(before.position, moved.position) do
      :clear ->
        {:ok, moved}

      {:hit, %{position: contact, part: part}} ->
        travelled = distance(before.position, moved.position)
        speed = travelled / dt
        damage = if speed <= 0, do: 0, else: min(100, max(1, ceil(speed / 10.0)))
        {damaged, report} = Combat.apply_damage(moved, damage)
        stopped = %{damaged |
          position: contact, destination: nil, route_waypoints: [],
          navigation_mode: :manual, throttle: 0.0, cruise_speed: 0.0,
          velocity: @zero_vector, rotation_input: @zero_rotation,
          angular_velocity: @zero_rotation
        }
        {:impact, stopped, %{
          station_id: GreenStarbase.id(), station_kind: :starbase,
          entity_id: before.id, hull_part: part,
          tick_speed_km_s: speed, damage: report
        }}
    end
  end

  defp pieces do
    boxes = Enum.map(@boxes, fn {name, center, half} ->
      {name, box_planes(center, half)}
    end)
    boxes ++ [
      {:upper_pyramid, pyramid_planes(1.0)},
      {:lower_pyramid, pyramid_planes(-1.0)}
    ]
  end

  defp box_planes({cx, cy, cz}, {hx, hy, hz}) do
    [
      {{1.0, 0.0, 0.0}, cx + hx}, {{-1.0, 0.0, 0.0}, -cx + hx},
      {{0.0, 1.0, 0.0}, cy + hy}, {{0.0, -1.0, 0.0}, -cy + hy},
      {{0.0, 0.0, 1.0}, cz + hz}, {{0.0, 0.0, -1.0}, -cz + hz}
    ]
  end

  defp pyramid_planes(sign) do
    # ConeGeometry(35, 42, 4), centred at scene Y ±30, rotated 45 degrees.
    # At any cross section the four polygon planes bound a square.
    # The sides converge at Y ±51 and terminate at the plane Y ±9.
    [
      {{0.0, -sign, 0.0}, -9.0},
      {{0.0, sign, 0.0}, 51.0},
      {{42.0, 35.0 * sign, 0.0}, 35.0 * 51.0},
      {{-42.0, 35.0 * sign, 0.0}, 35.0 * 51.0},
      {{0.0, 35.0 * sign, 42.0}, 35.0 * 51.0},
      {{0.0, 35.0 * sign, -42.0}, 35.0 * 51.0}
    ]
  end

  defp clip_segment(start, finish, planes) do
    if inside_planes?(start, planes) do
      # A restored/legacy pose already inside a wall must be expelled once.
      {_gap, normal} =
        planes
        |> Enum.map(fn {normal, limit} ->
          {(limit - dot(normal, start)) / length(normal), normal}
        end)
        |> Enum.min_by(&elem(&1, 0))
      push_out = @collision_separation_scene +
        max(0.0, Enum.min(Enum.map(planes, fn {n, d} ->
          (d - dot(n, start)) / length(n)
        end)))
      {0.0, add(start, multiply(normal, push_out / length(normal)))}
    else
      delta = subtract(finish, start)
      case Enum.reduce_while(planes, {0.0, 1.0, nil},
             fn {normal, limit}, {entry, exit_t, entry_normal} ->
        velocity = dot(normal, delta)
        gap = limit - dot(normal, start)

        cond do
          abs(velocity) < 1.0e-10 and gap < 0 ->
            {:halt, :miss}
          abs(velocity) < 1.0e-10 ->
            {:cont, {entry, exit_t, entry_normal}}
          velocity < 0 ->
            t = gap / velocity
            if t > exit_t, do: {:halt, :miss},
              else: {:cont, {max(t, entry), exit_t,
                if(t >= entry, do: normal, else: entry_normal)}}
          true ->
            t = gap / velocity
            if t < entry, do: {:halt, :miss},
              else: {:cont, {entry, min(t, exit_t), entry_normal}}
        end
      end) do
        :miss -> nil
        {t, exit_t, normal} when t <= 1.0 and t <= exit_t and not is_nil(normal) ->
          impact = add(start, multiply(delta, max(0.0, t)))
          # Conservative outward offset so the following idle tick won't
          # inflict repeated contact damage.
          {max(0.0, t),
           add(impact, multiply(normal,
             @collision_separation_scene / length(normal)))}
        _ -> nil
      end
    end
  end

  defp inside_planes?(p, planes),
    do: Enum.all?(planes, fn {n, d} -> dot(n, p) <= d end)

  defp scene_position(%Position{x: x, y: y, z: z}) do
    site = GreenStarbase.local_site()
    {(x - site.x) * @scale, (z - site.z) * @scale,
     (y - site.y) * @scale}
  end

  defp world_position({x, y, z}) do
    site = GreenStarbase.local_site()
    %Position{x: site.x + x / @scale, y: site.y + z / @scale,
      z: site.z + y / @scale}
  end

  defp dot({ax, ay, az}, {bx, by, bz}), do: ax*bx + ay*by + az*bz
  defp subtract({ax, ay, az}, {bx, by, bz}), do: {ax-bx, ay-by, az-bz}
  defp add({ax, ay, az}, {bx, by, bz}), do: {ax+bx, ay+by, az+bz}
  defp multiply({x, y, z}, s), do: {x*s, y*s, z*s}
  defp length({x, y, z}), do: :math.sqrt(x*x + y*y + z*z)
  defp distance(a, b) do
    dx = a.x - b.x
    dy = a.y - b.y
    dz = a.z - b.z
    :math.sqrt(dx*dx + dy*dy + dz*dz)
  end
end
