defmodule Core.World.StationSafetyTest do
  use ExUnit.Case, async: true

  alias Core.Universe.OrbitalEntry
  alias Core.World.{Entity, MapDefinition, Position, StationSafety}

  defp world do
    OrbitalEntry.planet_maps()
    |> Enum.find(&(&1.id == "sol:earth"))
  end

  defp station do
    OrbitalEntry.space_base("earth")
  end

  defp at(offset, z \\ 0.0) do
    base = station().position_3d
    %Position{x: base.x + offset, y: base.y, z: base.z + z}
  end

  defp ship(pos) do
    %Entity{
      id: 8, player_id: 8, session_id: 8, kind: :player,
      position: pos, speed: 320.0, hull: 200, max_hull: 200,
      shields: 0, max_shields: 0, shield_absorption: 0.0,
      damage: 10, attack_range: 3600.0,
      attack_cooldown_ticks: 1, next_attack_tick: 0,
      status: :alive
    }
  end

  test "station warning is independent of the planet warning" do
    assert StationSafety.warning(at(3_000), world()) == nil
    assert %{level: :caution, station_id: "sol:base:earth",
             clearance_km: clearance} = StationSafety.warning(at(2_000), world())
    assert_in_delta clearance, 1_400.0, 1.0e-6
    assert %{level: :critical} = StationSafety.warning(at(1_000), world())
    assert StationSafety.warning(at(1_000), MapDefinition.starting_map()) == nil
  end

  test "swept manual impact stops outside refinery and causes bounded hull damage" do
    before = ship(at(610))
    moved = %{before | position: at(570), velocity: %{x: -400.0, y: 0.0, z: 0.0},
      throttle: 1.0, cruise_speed: 400.0,
      destination: at(200), route_waypoints: [at(100)],
      navigation_mode: :autopilot}
    assert {:impact, stopped, report} = StationSafety.resolve(before, moved, world(), 0.1)
    assert report.station_id == "sol:base:earth"
    assert_in_delta report.tick_speed_km_s, 400.0, 0.001
    assert report.damage.requested_damage == 40
    assert stopped.status == :alive
    assert stopped.hull == 160
    assert_in_delta stopped.position.x, station().position_3d.x + 600.25, 0.001
    assert stopped.position.y == station().position_3d.y
    assert stopped.destination == nil
    assert stopped.route_waypoints == []
    assert stopped.throttle == 0
    assert stopped.velocity == %{x: 0.0, y: 0.0, z: 0.0}
    assert {:ok, _} = StationSafety.resolve(stopped, stopped, world(), 0.1)
  end

  test "tunneling and 3D vertical incursions hit, distant flybys stay clear" do
    first = ship(at(1_200))
    through = %{first | position: at(-1_200)}
    assert {:impact, _stopped, report} = StationSafety.resolve(first, through, world(), 0.1)
    assert report.damage.requested_damage == 100

    above = ship(at(0, 900))
    safe = %{above | position: at(100, 900)}
    assert {:ok, ^safe} = StationSafety.resolve(above, safe, world(), 0.1)
    lower = %{above | position: at(0, 580)}
    assert {:impact, _, _} = StationSafety.resolve(above, lower, world(), 0.1)
  end

  test "station collision never replaces the fatal planetary geometry" do
    far = ship(at(610))
    unsafe = %{far | position: at(500)}
    assert {:ok, ^unsafe} =
      StationSafety.resolve(far, unsafe, MapDefinition.starting_map(), 0.1)
  end

  test "impact damage respects shield absorption and may destroy exhausted hull" do
    before = %{ship(at(601)) | hull: 1, shields: 50, max_shields: 50,
       shield_absorption: 1.0}
    moved = %{before | position: at(599)}
    assert {:impact, stopped, %{damage: report}} =
      StationSafety.resolve(before, moved, world(), 0.1)
    assert report.shield_damage == 2
    assert stopped.hull == 1
    assert stopped.shields == 48

    exposed = %{before | shields: 0, shield_absorption: 0.0}
    assert {:impact, destroyed, _} = StationSafety.resolve(exposed, moved, world(), 0.1)
    assert destroyed.hull == 0
    assert destroyed.status == :destroyed
  end

  test "level transitions emit only once per boundary crossing" do
    cautious = StationSafety.warning(at(2_000), world())
    critical = StationSafety.warning(at(1_000), world())
    assert %{level: :caution, previous_level: :clear} =
      StationSafety.transition(8, nil, cautious, 1)
    assert StationSafety.transition(8, cautious, cautious, 2) == nil
    assert %{level: :critical, previous_level: :caution} =
      StationSafety.transition(8, cautious, critical, 3)
    assert %{level: :clear, previous_level: :critical, clearance_km: nil} =
      StationSafety.transition(8, critical, nil, 4)
  end
end
