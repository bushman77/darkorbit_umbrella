defmodule Core.World.FlightDynamicsTest do
  use ExUnit.Case, async: true

  alias Core.World.Entity
  alias Core.World.FlightDynamics
  alias Core.World.MapDefinition
  alias Core.World.Orientation
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

  test "orbital regions stop ships at a real-radius planetary safety boundary" do
    map = Core.Universe.OrbitalEntry.planet_maps()
      |> Enum.find(&(&1.id == "sol:venus"))
    planet = map.planet
    boundary = planet.exclusion_radius
    centre = planet.center

    approaching = %{ship() |
      position: %Position{x: centre.x + boundary + 3.0, y: centre.y, z: centre.z},
      flight_mode: :newtonian,
      velocity: %{x: -100.0, y: 0.0, z: 0.0},
      cruise_speed: 30.0
    }

    stopped = FlightDynamics.step(approaching, map, 0.1, 1)
    assert_in_delta stopped.position.x, centre.x + boundary, 1.0e-7
    assert_in_delta stopped.position.y, centre.y, 1.0e-7
    assert stopped.velocity == %{x: 0.0, y: 0.0, z: 0.0}
    assert stopped.cruise_speed == 0.0

    again = FlightDynamics.step(stopped, map, 0.1, 2)
    assert_in_delta again.position.x, centre.x + boundary, 1.0e-7
    assert again.velocity == %{x: 0.0, y: 0.0, z: 0.0}
  end

  test "planetary radius restrictions never apply to old combat fixtures" do
    map = MapDefinition.starting_map()
    assert map.planet == nil
    approaching = %{ship() |
      position: %Position{x: 1000.0, y: 1000.0},
      flight_mode: :newtonian,
      velocity: %{x: 100.0, y: 0.0, z: 0.0}
    }
    advanced = FlightDynamics.step(approaching, map, 0.1, 1)
    assert advanced.position.x > 1000.0
  end

  test "after rolling 90 degrees, pitch follows ship-local right axis" do
    map = MapDefinition.starting_map()
    rolled = %{ship() | orientation: Orientation.from_angles(%{
      yaw: 0.0, pitch: 0.0, roll: :math.pi() / 2
    })}
    {:ok, control} = FlightDynamics.controls(rolled, %{pitch: 1.0, throttle: 1.0}, 0)
    moving = FlightDynamics.step(control, map, 0.2, 1)
    nose = FlightDynamics.forward(moving)

    assert nose.x < -0.01
    assert_in_delta nose.z, 0.0, 1.0e-8
    assert moving.velocity.x < 0.0
    assert_in_delta moving.velocity.z, 0.0, 1.0e-8
  end

  test "pitch after yaw follows current heading, not spawn north" do
    map = MapDefinition.starting_map()
    east = %{ship() | orientation: Orientation.from_angles(%{
      yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0
    })}
    {:ok, control} = FlightDynamics.controls(east, %{pitch: 1.0, throttle: 1.0}, 0)
    moving = FlightDynamics.step(control, map, 0.2, 1)
    nose = FlightDynamics.forward(moving)

    assert nose.x > 0.0
    assert nose.z > 0.0
    assert_in_delta nose.y, 0.0, 1.0e-8
    assert_in_delta moving.velocity.z, moving.cruise_speed * nose.z, 1.0e-8
  end

  test "yaw after roll acts around the rotated local up axis" do
    map = MapDefinition.starting_map()
    rolled = %{ship() | orientation: Orientation.from_angles(%{
      yaw: 0.0, pitch: 0.0, roll: :math.pi() / 2
    })}
    {:ok, control} = FlightDynamics.controls(rolled, %{yaw: 1.0}, 0)
    turned = FlightDynamics.step(control, map, 0.2, 1)
    assert_in_delta FlightDynamics.forward(turned).x, 0.0, 1.0e-8
    assert FlightDynamics.forward(turned).z > 0
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

  test "assisted throttle approaches target speed over ticks and brakes progressively" do
    map = MapDefinition.starting_map()
    {:ok, full} = FlightDynamics.controls(ship(), %{throttle: 1.0, mode: "cruise"}, 0)
    first = FlightDynamics.step(full, map, 0.1, 1)
    second = FlightDynamics.step(first, map, 0.1, 2)

    # At 200 u/s maximum, cruise accelerates 150 u/s^2: 15 u/s per tick.
    assert_in_delta first.cruise_speed, 15.0, 1.0e-8
    assert_in_delta second.cruise_speed, 30.0, 1.0e-8
    assert second.cruise_speed < second.speed

    {:ok, idle} = FlightDynamics.controls(second, %{throttle: 0.0}, 2)
    braking = FlightDynamics.step(idle, map, 0.1, 3)
    assert braking.cruise_speed > 0.0
    assert braking.cruise_speed < second.cruise_speed
    assert_in_delta braking.cruise_speed, 6.0, 1.0e-8

    stopped = FlightDynamics.step(braking, map, 0.1, 4)
    assert stopped.cruise_speed == 0.0
    assert stopped.velocity == %{x: 0.0, y: -0.0, z: 0.0}
  end

  test "Newtonian mode coasts when the wheel selects zero thrust" do
    map = MapDefinition.starting_map()
    {:ok, launched} =
      FlightDynamics.controls(ship(), %{throttle: 1.0, mode: "newtonian"}, 0)
    moving = FlightDynamics.step(launched, map, 0.1, 1)
    {:ok, neutral} =
      FlightDynamics.controls(moving, %{throttle: 0.0, mode: "newtonian"}, 1)
    coast = FlightDynamics.step(neutral, map, 0.1, 2)

    assert coast.position.y < moving.position.y
    assert_in_delta coast.velocity.y, moving.velocity.y, 1.0e-8
    assert_in_delta coast.velocity.x, moving.velocity.x, 1.0e-8
  end

  test "accelerating after turning follows the current heading, never the spawn heading" do
    map = MapDefinition.starting_map()
    {:ok, launched} = FlightDynamics.controls(ship(), %{throttle: 1.0}, 0)
    moving_north = FlightDynamics.step(launched, map, 0.1, 1)

    assert moving_north.velocity.y < 0.0
    assert_in_delta moving_north.velocity.x, 0.0, 1.0e-8

    # Pilot turns to face east before accelerating further. The last
    # northward velocity must not dictate the new cruise travel direction.
    facing_east = %{moving_north |
      attitude: %{yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0},
      orientation: nil,
      angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0}}
    {:ok, thrusting_east} = FlightDynamics.controls(facing_east, %{throttle: 1.0}, 1)
    after_turn = FlightDynamics.step(thrusting_east, map, 0.1, 2)

    assert after_turn.velocity.x > 0
    assert_in_delta after_turn.velocity.y, 0.0, 1.0e-8
    assert after_turn.position.x > facing_east.position.x
    assert_in_delta after_turn.position.y, facing_east.position.y, 1.0e-8
    assert after_turn.cruise_speed > moving_north.cruise_speed
  end

  test "cruise movement remains aligned with live nose during a sustained turn" do
    map = MapDefinition.starting_map()
    {:ok, pilot} = FlightDynamics.controls(ship(), %{throttle: 0.8, yaw: 1.0}, 0)

    moving =
      Enum.reduce(1..8, pilot, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    nose = FlightDynamics.forward(moving.attitude)
    assert moving.velocity.x > 0.0
    assert moving.velocity.y < 0.0
    assert_in_delta moving.velocity.x, nose.x * moving.cruise_speed, 1.0e-8
    assert_in_delta moving.velocity.y, nose.y * moving.cruise_speed, 1.0e-8
    assert_in_delta moving.velocity.z, nose.z * moving.cruise_speed, 1.0e-8
  end

  test "pitch redirects cruise thrust into altitude, and roll alone does not" do
    map = MapDefinition.starting_map()
    attitude = %{yaw: :math.pi() / 3, pitch: :math.pi() / 4, roll: 1.2}
    ship = %{ship() | attitude: attitude}
    {:ok, engaged} = FlightDynamics.controls(ship, %{throttle: 1.0}, 0)
    moved = FlightDynamics.step(engaged, map, 0.1, 1)

    heading = FlightDynamics.forward(attitude)
    assert moved.position.x > ship.position.x
    assert moved.position.y < ship.position.y
    assert moved.position.z > ship.position.z
    assert_in_delta moved.velocity.x, moved.cruise_speed * heading.x, 1.0e-8
    assert_in_delta moved.velocity.z, moved.cruise_speed * heading.z, 1.0e-8

    rolled = %{ship | attitude: %{attitude | roll: -1.2}}
    {:ok, rolled_engaged} = FlightDynamics.controls(rolled, %{throttle: 1.0}, 0)
    rolled_moved = FlightDynamics.step(rolled_engaged, map, 0.1, 1)
    assert_in_delta rolled_moved.velocity.x, moved.velocity.x, 1.0e-8
    assert_in_delta rolled_moved.velocity.y, moved.velocity.y, 1.0e-8
    assert_in_delta rolled_moved.velocity.z, moved.velocity.z, 1.0e-8
  end

  test "Newtonian-to-Cruise transition aligns retained forward momentum with nose" do
    map = MapDefinition.starting_map()
    drifting = %{ship() | flight_mode: :newtonian,
      attitude: %{yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0},
      velocity: %{x: 40.0, y: -60.0, z: 0.0}}
    {:ok, cruise} =
      FlightDynamics.controls(drifting, %{mode: "cruise", throttle: 0.0}, 2)

    assert_in_delta cruise.cruise_speed, 40.0, 1.0e-8
    moved = FlightDynamics.step(cruise, map, 0.1, 3)
    assert moved.velocity.x > 0
    assert_in_delta moved.velocity.y, 0.0, 1.0e-8
    assert moved.cruise_speed < 40
  end

  test "reversed throttle after turning travels behind the current nose" do
    map = MapDefinition.starting_map()
    facing_east = %{ship() | attitude: %{yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0}}
    {:ok, reverse} = FlightDynamics.controls(facing_east, %{throttle: -1.0}, 0)
    backwards = FlightDynamics.step(reverse, map, 0.1, 1)

    assert backwards.velocity.x < 0
    assert_in_delta backwards.velocity.y, 0.0, 1.0e-8
    assert backwards.position.x < facing_east.position.x
  end

  test "Newtonian thrust follows nose but retains existing sideways inertia" do
    map = MapDefinition.starting_map()
    drifting_north = %{ship() | flight_mode: :newtonian,
      attitude: %{yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0},
      velocity: %{x: 0.0, y: -40.0, z: 0.0}}
    {:ok, thrust} =
      FlightDynamics.controls(drifting_north, %{mode: "newtonian", throttle: 1.0}, 0)
    after_thrust = FlightDynamics.step(thrust, map, 0.1, 1)

    assert after_thrust.velocity.x > 0
    assert_in_delta after_thrust.velocity.y, -40.0, 1.0e-8
    assert after_thrust.position.x > drifting_north.position.x
    assert after_thrust.position.y < drifting_north.position.y
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

    at_edge = %{oriented | flight_mode: :newtonian,
                              position: %Position{x: 1000.0, y: 1000.0, z: 2999.0},
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

  test "captured mouse steering has higher bounded yaw/pitch response than keyboard" do
    map = MapDefinition.starting_map()

    {:ok, keyboard} = FlightDynamics.controls(ship(), %{yaw: 1.0, pitch: 1.0}, 0)
    {:ok, mouse} =
      FlightDynamics.controls(ship(),
        %{yaw: 1.0, pitch: 1.0, mouse_steering: true}, 0)

    keyboard_first = FlightDynamics.step(keyboard, map, 0.1, 1)
    mouse_first = FlightDynamics.step(mouse, map, 0.1, 1)

    assert mouse_first.angular_velocity.yaw > keyboard_first.angular_velocity.yaw
    assert mouse_first.angular_velocity.pitch > keyboard_first.angular_velocity.pitch

    keyboard_full =
      Enum.reduce(2..10, keyboard_first, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    mouse_full =
      Enum.reduce(2..10, mouse_first, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    deg = 180.0 / :math.pi()
    assert_in_delta keyboard_full.angular_velocity.yaw * deg, 44.0, 1.0e-6
    assert_in_delta keyboard_full.angular_velocity.pitch * deg, 38.0, 1.0e-6
    assert_in_delta mouse_full.angular_velocity.yaw * deg, 100.0, 1.0e-6
    assert_in_delta mouse_full.angular_velocity.pitch * deg, 88.0, 1.0e-6

    # Releasing mouse capture reverts to the keyboard profile, including
    # bounded angular braking rather than an abrupt physical attitude jump.
    {:ok, released} =
      FlightDynamics.controls(mouse_full,
        %{yaw: 0.0, pitch: 0.0, mouse_steering: false}, 10)
    braking = FlightDynamics.step(released, map, 0.1, 11)

    assert braking.angular_velocity.yaw < mouse_full.angular_velocity.yaw
    assert braking.angular_velocity.pitch < mouse_full.angular_velocity.pitch
    assert braking.angular_velocity.yaw >= 0.0
    assert braking.angular_velocity.pitch >= 0.0
  end

  test "mouse-look neutral input stops yaw and pitch on the next simulation tick" do
    map = MapDefinition.starting_map()
    {:ok, captured} =
      FlightDynamics.controls(ship(),
        %{yaw: 1.0, pitch: -1.0, mouse_steering: true}, 0)
    rotating = FlightDynamics.step(captured, map, 0.1, 1)
    assert rotating.angular_velocity.yaw > 0.0
    assert rotating.angular_velocity.pitch < 0.0

    {:ok, neutral} =
      FlightDynamics.controls(rotating,
        %{yaw: 0.0, pitch: 0.0, mouse_steering: true}, 1)
    stopped = FlightDynamics.step(neutral, map, 0.1, 2)

    assert stopped.angular_velocity.yaw == 0.0
    assert stopped.angular_velocity.pitch == 0.0
    assert_in_delta stopped.attitude.yaw, rotating.attitude.yaw, 1.0e-12
    assert_in_delta stopped.attitude.pitch, rotating.attitude.pitch, 1.0e-12
  end

  test "mouse input stops an inactive axis while allowing the other to steer" do
    map = MapDefinition.starting_map()
    {:ok, captured} =
      FlightDynamics.controls(ship(),
        %{yaw: 1.0, pitch: 1.0, mouse_steering: true}, 0)
    rotating = FlightDynamics.step(captured, map, 0.1, 1)

    {:ok, vertical_only} =
      FlightDynamics.controls(rotating,
        %{yaw: 0.0, pitch: 1.0, mouse_steering: true}, 1)
    next = FlightDynamics.step(vertical_only, map, 0.1, 2)

    assert next.angular_velocity.yaw == 0.0
    assert next.angular_velocity.pitch > 0.0
    assert_in_delta next.attitude.yaw, rotating.attitude.yaw, 1.0e-12
  end

  test "releasing mouse capture cancels residual mouse angular velocity" do
    map = MapDefinition.starting_map()
    {:ok, captured} =
      FlightDynamics.controls(ship(),
        %{yaw: 1.0, pitch: 1.0, mouse_steering: true}, 0)
    rotating = FlightDynamics.step(captured, map, 0.1, 1)

    {:ok, released} =
      FlightDynamics.controls(rotating,
        %{yaw: 0.0, pitch: 0.0, mouse_steering: false}, 1)
    assert released.angular_velocity.yaw == 0.0
    assert released.angular_velocity.pitch == 0.0

    stopped = FlightDynamics.step(released, map, 0.1, 2)
    assert stopped.angular_velocity.yaw == 0.0
    assert stopped.angular_velocity.pitch == 0.0
    assert_in_delta stopped.attitude.yaw, rotating.attitude.yaw, 1.0e-12
    assert_in_delta stopped.attitude.pitch, rotating.attitude.pitch, 1.0e-12
  end

  test "stale mouse-only input also snaps to neutral on expiry" do
    map = MapDefinition.starting_map()
    {:ok, captured} =
      FlightDynamics.controls(ship(), %{yaw: 1.0, mouse_steering: true}, 0)
    after_expiry =
      Enum.reduce(1..16, captured, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    assert after_expiry.angular_velocity.yaw == 0.0
  end

  test "untrusted mouse steering mode must be boolean and cannot override rotation bounds" do
    assert {:error, :invalid_flight_controls} =
      FlightDynamics.controls(ship(), %{yaw: 1.0, mouse_steering: "fast"}, 0)
    assert {:error, :invalid_flight_controls} =
      FlightDynamics.controls(ship(), %{yaw: 8.0, mouse_steering: true}, 0)
    assert {:error, :invalid_flight_controls} =
      FlightDynamics.controls(ship(), %{pitch: -8.0, mouse_steering: true}, 0)
  end

  test "a held pitch key ramps smoothly to a capped rate without jumping" do
    map = MapDefinition.starting_map()
    {:ok, started} = FlightDynamics.controls(ship(), %{pitch: 1.0}, 0)
    first = FlightDynamics.step(started, map, 0.1, 1)
    second = FlightDynamics.step(first, map, 0.1, 2)

    first_rate = first.angular_velocity.pitch * 180.0 / :math.pi()
    second_rate = second.angular_velocity.pitch * 180.0 / :math.pi()
    assert first_rate > 0 and first_rate < 38.0
    assert second_rate > first_rate
    assert first.attitude.pitch > 0 and first.attitude.pitch < 0.02

    at_cap =
      Enum.reduce(3..10, second, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    assert_in_delta at_cap.angular_velocity.pitch * 180.0 / :math.pi(), 38.0, 1.0e-6
  end

  test "releasing steering brakes smoothly and stops without snap or reverse" do
    map = MapDefinition.starting_map()
    {:ok, started} = FlightDynamics.controls(ship(), %{yaw: 1.0}, 0)
    turning =
      Enum.reduce(1..5, started, fn tick, current ->
        FlightDynamics.step(current, map, 0.1, tick)
      end)

    {:ok, released} = FlightDynamics.controls(turning, %{yaw: 0.0}, 5)
    first = FlightDynamics.step(released, map, 0.1, 6)
    assert first.angular_velocity.yaw > 0
    assert first.angular_velocity.yaw < turning.angular_velocity.yaw
    assert first.attitude.yaw > turning.attitude.yaw

    stopped = Enum.reduce(7..15, first, fn tick, current ->
      FlightDynamics.step(current, map, 0.1, tick)
    end)
    assert stopped.angular_velocity.yaw == 0.0
    assert stopped.attitude.yaw > turning.attitude.yaw
    assert stopped.attitude.yaw < turning.attitude.yaw + 0.2
  end

  test "opposite steering must decelerate before changing sign" do
    map = MapDefinition.starting_map()
    {:ok, started} = FlightDynamics.controls(ship(), %{roll: 1.0}, 0)
    turning = Enum.reduce(1..6, started, fn tick, current ->
      FlightDynamics.step(current, map, 0.1, tick)
    end)
    assert turning.angular_velocity.roll > 0

    {:ok, reverse} = FlightDynamics.controls(turning, %{roll: -1.0}, 6)
    first = FlightDynamics.step(reverse, map, 0.1, 7)
    assert first.angular_velocity.roll < turning.angular_velocity.roll
    assert first.angular_velocity.roll > 0

    backwards = Enum.reduce(8..15, first, fn tick, current ->
      FlightDynamics.step(current, map, 0.1, tick)
    end)
    assert backwards.angular_velocity.roll < 0.0
  end

  test "stale rotational inputs brake to zero instead of rotating forever" do
    map = MapDefinition.starting_map()
    {:ok, started} = FlightDynamics.controls(ship(), %{yaw: 1.0}, 0)
    after_expiry = Enum.reduce(1..16, started, fn tick, current ->
      FlightDynamics.step(current, map, 0.1, tick)
    end)

    assert after_expiry.angular_velocity.yaw == 0.0
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
    inverted = %{ship() | attitude: %{yaw: 0.0, pitch: -1.4, roll: 0.0}}
    {:ok, descending} = FlightDynamics.controls(inverted, %{pitch: -1.0}, 0)

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
    # With rotational inertia, the first reverse tick can still rotate up
    # while the server brakes. The *rate* must immediately decrease.
    assert descending.angular_velocity.pitch < rising.angular_velocity.pitch
    {:ok, sustained} = FlightDynamics.controls(descending, %{pitch: -1.0}, 2)
    reversed = Enum.reduce(3..8, sustained, fn tick, current ->
      FlightDynamics.step(current, map, 0.2, tick)
    end)
    assert reversed.attitude.pitch < rising.attitude.pitch
    assert reversed.angular_velocity.pitch < 0.0
  end

  test "rotation input expires without renewed commands" do
    map = MapDefinition.starting_map()
    {:ok, turning} = FlightDynamics.controls(ship(), %{yaw: 1.0}, 0)
    after_expiry = FlightDynamics.step(turning, map, 0.1, 12)
    assert after_expiry.attitude.yaw == 0.0
  end
end
