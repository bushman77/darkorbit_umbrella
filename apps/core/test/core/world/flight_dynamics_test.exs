defmodule Core.World.FlightDynamicsTest do
  use ExUnit.Case, async: true

  alias Core.World.Entity
  alias Core.World.FlightDynamics
  alias Core.World.MapDefinition
  alias Core.World.Position

  defp ship do
    %Entity{
      id: 1, kind: :player, player_id: 1, session_id: 1,
      position: %Position{x: 1000.0, y: 1000.0},
      speed: 200.0, hull: 100, max_hull: 100, shields: 0, max_shields: 0,
      shield_absorption: 0.0, damage: 1, attack_range: 720.0,
      attack_cooldown_ticks: 1, next_attack_tick: 0, status: :alive
    }
  end

  test "signed cruise throttle accelerates forward then brakes and reverses" do
    map = MapDefinition.starting_map()
    {:ok, forward} = FlightDynamics.controls(ship(), %{throttle: 0.5}, 0)
    first = FlightDynamics.step(forward, map, 0.1, 1)
    assert first.position.y < forward.position.y
    assert first.velocity.y < 0

    {:ok, neutral} = FlightDynamics.controls(first, %{throttle: 0.0}, 1)
    braked = FlightDynamics.step(neutral, map, 0.1, 2)
    assert abs(braked.velocity.y) < abs(first.velocity.y)

    {:ok, reverse} = FlightDynamics.controls(braked, %{throttle: -1.0}, 2)
    final =
      Enum.reduce(3..20, reverse, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    assert final.velocity.y > 0
  end

  test "Newtonian motion persists at zero throttle while rotation changes heading" do
    map = MapDefinition.starting_map()
    {:ok, started} = FlightDynamics.controls(ship(), %{throttle: 1.0, mode: "newtonian"}, 0)
    moving = FlightDynamics.step(started, map, 0.1, 1)
    assert moving.velocity.y < 0

    {:ok, coasting} =
      FlightDynamics.controls(moving, %{throttle: 0.0, mode: "newtonian", yaw: 1.0}, 1)

    turned = FlightDynamics.step(coasting, map, 0.1, 2)
    assert turned.attitude.yaw > 0
    assert_in_delta turned.velocity.y, moving.velocity.y, 1.0e-8
    assert_in_delta turned.velocity.x, moving.velocity.x, 1.0e-8
    assert turned.position.y < moving.position.y
  end

  test "pitch changes vertical thrust and limits block leaving the sector" do
    map = MapDefinition.starting_map()
    {:ok, pitched} = FlightDynamics.controls(ship(), %{pitch: 1.0, throttle: 1.0}, 0)
    oriented = FlightDynamics.step(pitched, map, 0.5, 1)
    assert oriented.attitude.pitch > 0.0
    assert oriented.position.z > 0.0

    at_edge = %{oriented | position: %Position{x: 1000.0, y: 1000.0, z: 2999.0},
                              velocity: %{x: 0.0, y: 0.0, z: 500.0}}
    clamped = FlightDynamics.step(at_edge, map, 0.1, 2)
    assert clamped.position.z <= 3000.0
    assert clamped.velocity.z == 0.0
  end

  test "malformed input cannot change the ship or override its route" do
    flight = %{ship() | destination: %Position{x: 1500.0, y: 1000.0},
                        route_waypoints: [%Position{x: 1800.0, y: 1000.0}],
                        navigation_mode: :autopilot}

    assert {:error, :invalid_flight_controls} =
             FlightDynamics.controls(flight, %{throttle: 2.0}, 0)

    assert {:error, :invalid_flight_controls} =
             FlightDynamics.controls(flight, %{yaw: "spoof"}, 0)

    assert {:error, :invalid_flight_controls} =
             FlightDynamics.controls(flight, %{mode: "warp"}, 0)

    assert {:ok, updated} =
             FlightDynamics.controls(flight, %{yaw: -1.0, throttle: 0.0}, 0)

    assert updated.navigation_mode == :manual
    assert updated.destination == nil
    assert updated.route_waypoints == []
  end

  test "yaw and roll remain independent server-owned attitude axes" do
    map = MapDefinition.starting_map()
    {:ok, yaw} = FlightDynamics.controls(ship(), %{yaw: 1.0}, 0)
    {:ok, roll} = FlightDynamics.controls(ship(), %{roll: 1.0}, 0)
    turned = FlightDynamics.step(yaw, map, 0.2, 1)
    banked = FlightDynamics.step(roll, map, 0.2, 1)

    assert turned.attitude.yaw > 0
    assert turned.attitude.roll == 0.0
    assert banked.attitude.roll > 0
    assert banked.attitude.yaw == 0.0
    assert FlightDynamics.forward(turned.attitude).x > 0
    assert FlightDynamics.forward(banked.attitude).x == 0.0
  end

  test "S can pitch down through vertical without stopping at minus 89 degrees" do
    map = MapDefinition.starting_map()
    {:ok, descending} = FlightDynamics.controls(ship(), %{pitch: -1.0}, 0)

    turned =
      Enum.reduce(1..8, descending, fn tick, entity ->
        FlightDynamics.step(entity, map, 0.2, tick)
      end)

    assert turned.attitude.pitch < -:math.pi() / 2
    assert turned.attitude.pitch > -:math.pi()
    assert FlightDynamics.forward(turned.attitude).z < 0.0
  end

  test "W and S are opposite server pitch commands" do
    map = MapDefinition.starting_map()
    {:ok, up} = FlightDynamics.controls(ship(), %{pitch: 1.0}, 0)
    rising = FlightDynamics.step(up, map, 0.2, 1)
    assert rising.attitude.pitch > 0.0

    {:ok, down} = FlightDynamics.controls(rising, %{pitch: -1.0}, 1)
    descending = FlightDynamics.step(down, map, 0.2, 2)
    assert_in_delta descending.attitude.pitch, 0.0, 1.0e-8
  end

  test "rotation input expires without renewed commands" do
    map = MapDefinition.starting_map()
    {:ok, turning} = FlightDynamics.controls(ship(), %{yaw: 1.0}, 0)
    after_expiry = FlightDynamics.step(turning, map, 0.1, 12)
    assert after_expiry.attitude.yaw == 0.0
  end
end
