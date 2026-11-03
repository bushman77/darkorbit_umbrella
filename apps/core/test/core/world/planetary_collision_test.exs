defmodule Core.World.PlanetaryCollisionTest do
  use ExUnit.Case, async: true

  alias Core.World.Entity
  alias Core.World.PlanetaryCollision
  alias Core.World.MapDefinition
  alias Core.World.Position
  alias Core.Universe.OrbitalEntry

  @center %{x: 200_000.0, y: 200_000.0, z: 0.0}
  @radius 6_536.0

  defp pos(x, y \ 0.0, z \ 0.0) do
    %Position{x: @center.x + x, y: @center.y + y, z: z}
  end

  defp ship(position) do
    %Entity{
      id: 3, player_id: 3, session_id: 3, kind: :player,
      position: position, status: :alive,
      speed: 320.0, hull: 125, max_hull: 125,
      shields: 500, max_shields: 500, shield_absorption: 1.0,
      damage: 2, attack_range: 720.0,
      attack_cooldown_ticks: 1, next_attack_tick: 0
    }
  end

  defp map do
    OrbitalEntry.planet_maps()
    |> Enum.find(&(&1.id == "sol:venus"))
  end

  test "normal arrival and outward or tangential travel remain safe" do
    orbital = map()
    radius = orbital.planet.exclusion_radius
    start = ship(pos(radius * 1.861))
    assert {:ok, ^start} = PlanetaryCollision.resolve(start, start, orbital)

    away = %{start | position: pos(radius * 1.861 + 100)}
    assert {:ok, ^away} = PlanetaryCollision.resolve(start, away, orbital)

    assert :clear = PlanetaryCollision.first_contact(
      pos(radius + 100, 200), pos(radius + 120, 300), @center, radius)
  end

  test "crossing Venus boundary kills instantly despite maximum shield absorption" do
    orbital = map()
    radius = orbital.planet.exclusion_radius
    start = ship(pos(radius + 12))
    moved = %{start | position: pos(radius - 20),
      velocity: %{x: -320.0, y: 0.0, z: 0.0},
      cruise_speed: -320.0, throttle: -1.0,
      target_id: "npc:enemy", engaged_target_id: "npc:enemy",
      destination: pos(radius - 300), route_waypoints: [pos(radius - 350)],
      navigation_mode: :autopilot}

    assert {:crashed, destroyed} = PlanetaryCollision.resolve(start, moved, orbital)
    assert_in_delta destroyed.position.x, @center.x + radius, 1.0e-7
    assert destroyed.position.y == @center.y
    assert destroyed.status == :destroyed
    assert destroyed.hull == 0
    assert destroyed.shields == 0
    assert destroyed.velocity == %{x: 0.0, y: 0.0, z: 0.0}
    assert destroyed.cruise_speed == 0.0
    assert destroyed.throttle == 0.0
    assert destroyed.destination == nil
    assert destroyed.route_waypoints == []
    assert destroyed.target_id == nil
    assert destroyed.engaged_target_id == nil
    assert destroyed.angular_velocity == %{x: 0.0, y: 0.0, z: 0.0} or
      destroyed.angular_velocity == %{yaw: 0.0, pitch: 0.0, roll: 0.0}
    assert {:ok, ^destroyed} =
      PlanetaryCollision.resolve(destroyed, destroyed, orbital)
  end

  test "continuous segment intersection prevents passing through the whole planet" do
    radius = map().planet.exclusion_radius
    from = pos(radius + 200)
    through = pos(-radius - 200)

    assert {:hit, first} =
      PlanetaryCollision.first_contact(from, through, @center, radius)
    assert_in_delta first.x, @center.x + radius, 1.0e-7
    assert_in_delta first.y, @center.y, 1.0e-7
    assert {:crashed, dead} =
      PlanetaryCollision.resolve(ship(from), ship(through), map())
    assert dead.status == :destroyed
  end

  test "3D altitude is respected and missing planet geometry cannot kill" do
    orbital = map()
    radius = orbital.planet.exclusion_radius
    above = ship(pos(0, 0, radius + 50))
    higher = %{above | position: pos(-100, 0, radius + 50)}
    assert {:ok, ^higher} = PlanetaryCollision.resolve(above, higher, orbital)

    dive = %{above | position: pos(0, 0, radius - 100)}
    assert {:crashed, _} = PlanetaryCollision.resolve(above, dive, orbital)
    assert {:ok, ^dive} =
      PlanetaryCollision.resolve(above, dive, MapDefinition.starting_map())
  end

  test "an invalid position already within the collision volume is fatal" do
    before = ship(pos(0))
    after_move = %{before | position: pos(500)}
    assert {:crashed, dead} = PlanetaryCollision.resolve(before, after_move, map())
    assert dead.position == before.position
  end
end
