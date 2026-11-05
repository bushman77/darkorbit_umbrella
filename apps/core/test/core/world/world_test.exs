defmodule Core.WorldTest do
  use ExUnit.Case

  alias Core.Ships.Stats
  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.Universe.FreeFlightRegion
  alias Core.World
  alias Core.World.MapDefinition
  alias Core.World.Orientation
  alias Core.World.Supervisor, as: WorldSupervisor

  @registry Core.WorldTest.Registry
  @sessions Core.WorldTest.Sessions
  @solar_navigation_server Core.WorldTest.SolarNavigation
  @supervisor Core.WorldTest.Supervisor

  setup tags do
    test_process = self()
    event_sink = fn map_id, event, payload -> send(test_process, {map_id, event, payload}) end

    start_supervised!(
      {WorldSupervisor,
       name: @supervisor,
       registry: @registry,
       sessions: @sessions,
       solar_navigation_server: @solar_navigation_server,
       maps: [MapDefinition.starting_map()],
       tick_ms: 100,
       auto_tick: false,
       initial_npcs?: !Map.get(tags, :no_initial_encounter, false),
       auto_respawn?: !Map.get(tags, :no_auto_respawn, false),
       procedural_contact_chance: 0.0,
       event_sink: event_sink}
    )

    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    %{stats: stats,
      world_options: [registry: @registry, sessions: @sessions,
        solar_navigation_server: @solar_navigation_server]}
  end

  @tag no_initial_encounter: true
  test "manual free-flight is isolated to its private map and resumes the same voyage", context do
    options = Keyword.merge(context.world_options,
      event_sink: fn _map, _event, _payload -> :ok end, auto_tick: false,
      tick_ms: 100)

    assert {:ok, original} = World.connect(341, context.stats, options)
    assert {:ok, started} = World.solar_set_course(original.id, "mars", options)
    assert {:error, :interplanetary_cruise_active} =
      World.flight_controls(original.id, %{"throttle" => 0.5}, options)

    assert {:ok, paused} = World.solar_enter_free_flight(original.id, options)
    assert paused.free_flight
    assert paused.position_km == started.position_km
    assert {:error, :wrong_flight_region} =
      World.flight_controls(original.id, %{"throttle" => 0.5}, options)

    assert :ok = World.disconnect(original.id, options)
    assert {:ok, entry} = FreeFlightRegion.entry(341, paused)
    assert {:ok, free} = World.connect(341, context.stats,
      Keyword.merge(options, map_id: entry.map_id, entry: entry))
    assert {:ok, _} = World.flight_controls(free.id, %{"throttle" => 0.5}, options)
    assert {:ok, continued} = World.solar_resume_cruise(free.id, options)
    assert continued.position_km == paused.position_km
    assert continued.voyage_number == started.voyage_number
    assert {:error, :interplanetary_cruise_active} =
      World.flight_controls(free.id, %{"throttle" => 0.5}, options)
    assert :ok = World.disconnect(free.id, options)
    refute Core.World.MapServer.available?(@registry, entry.map_id)
    assert {:ok, snapshot} = SolarNavigation.snapshot(@solar_navigation_server, 341)
    refute snapshot.free_flight
  end

  @tag no_initial_encounter: true
  test "headless simulation moves a ship across the map on deterministic ticks", context do
    assert {:ok, session} = World.connect(:pilot_one, context.stats, context.world_options)
    assert_receive {"1-1", :entity_joined, %{player_id: :pilot_one}}

    assert {:ok, initial} = World.snapshot("1-1", context.world_options)
    assert initial.tick == 0
    assert initial.tick_ms == 100
    player = Enum.find(initial.entities, &(&1.kind == :player))
    assert player.position == %{x: 1_000.0, y: 1_000.0}
    assert Enum.count(initial.entities, &(&1.kind == :npc)) == 0

    assert {:ok, command_state} =
             World.move(session.id, %{x: 1_128.0, y: 1_000.0}, context.world_options)

    assert command_state.position == %{x: 1_000.0, y: 1_000.0}

    snapshots =
      for _tick <- 1..4 do
        assert {:ok, snapshot} = World.tick("1-1", context.world_options)
        snapshot
      end

    final = List.last(snapshots)
    assert final.tick == 4

    %{position: %{x: x, y: y}, destination: nil} =
      Enum.find(final.entities, &(&1.kind == :player))

    assert_in_delta x, 1_128.0, 0.000_001
    assert_in_delta y, 1_000.0, 0.000_001
  end

  @tag no_initial_encounter: true
  test "server-only encounter registration creates exactly one Dart", context do
    assert {:ok, initial} = World.snapshot("1-1", context.world_options)
    refute Enum.any?(initial.entities, &(&1.kind == :npc))
    assert {:error, :unknown_npc_type} = World.start_encounter("unknown", context.world_options)
    assert {:ok, npc} = World.start_encounter("dart", context.world_options)
    assert npc.id == "npc:1-1:dart:1"
    assert npc.hull == 245
    assert {:error, :encounter_active} = World.start_encounter("dart", context.world_options)
    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    assert Enum.count(snapshot.entities, &(&1.kind == :npc)) == 1
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "completed encounter stays cleared; Dart never respawns on its own", context do
    assert {:ok, _npc} = World.start_encounter("dart", context.world_options)
    stats = %{context.stats | damage: 1_200}
    assert {:ok, session} = World.connect(:peaceful_hunter, stats, context.world_options)
    assert {:ok, _selection} =
      World.select_target(session.id, "npc:1-1:dart:1", context.world_options)
    assert {:ok, %{destroyed: true, respawn_tick: nil}} =
      World.attack(session.id, context.world_options)
    for _ <- 1..40, do: assert({:ok, _} = World.tick("1-1", context.world_options))
    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    refute Enum.any?(snapshot.entities, &(&1.kind == :npc))
  end

  @tag no_initial_encounter: true
  test "SOL routes are session authorized, Earth-based and independent of combat XY", context do
    assert {:ok, session} = World.connect(981, context.stats, context.world_options)
    opts = context.world_options
    assert {:ok, %{location_id: "earth", status: :idle}} =
      World.solar_snapshot(session.id, opts)
    assert {:error, :session_not_found} = World.solar_set_course(-1, "mars", opts)
    assert {:error, :invalid_solar_destination} =
      World.solar_set_course(session.id, "sun", opts)
    assert {:ok, %{destination_id: "mars", status: :traveling,
                    propulsion_mode: :interplanetary_cruise}} =
      World.solar_set_course(session.id, "mars", opts)
    assert {:error, :interplanetary_cruise_active} =
      World.move(session.id, %{x: 1_200, y: 1_200}, opts)
    assert {:error, :interplanetary_cruise_active} =
      World.plot_course(session.id, [%{x: 1_250, y: 1_250}], opts)
    assert {:error, :interplanetary_cruise_active} =
      World.flight_controls(session.id, %{}, opts)
    assert {:error, :interplanetary_cruise_active} =
      World.fire_ready_weapon(session.id, opts)
    assert {:error, :interplanetary_cruise_active} =
      World.attack(session.id, opts)
    assert {:error, :already_traveling} =
      World.solar_set_course(session.id, "pluto", opts)
    assert :ok = SolarNavigation.tick(@solar_navigation_server)
    assert {:ok, %{progress: progress}} = World.solar_snapshot(session.id, opts)
    assert progress > 0
    assert {:ok, sector} = World.snapshot("1-1", opts)
    assert Enum.find(sector.entities, &(&1.id == 981)).position ==
      %{x: 1_000.0, y: 1_000.0}
    refute Enum.any?(sector.entities, &(&1.kind == :npc))
    assert {:ok, %{status: :idle, location_id: nil,
                    propulsion_mode: :conventional}} =
      World.solar_cancel_course(session.id, opts)
    # The old Earth tactical map is no longer a valid way to move a pilot
    # whose authoritative SOL location is now in deep space.
    assert {:error, :wrong_flight_region} =
      World.move(session.id, %{x: 1_200, y: 1_200}, opts)
  end

  @tag no_initial_encounter: true
  test "SOL traffic hails require the active pilot's authenticated session", context do
    assert {:ok, session} = World.connect(1_043, context.stats, context.world_options)
    assert {:error, :session_not_found} =
      World.solar_hail(-1, "traffic:sol:meridian-01", context.world_options)

    assert {:ok, navigation} = World.solar_snapshot(session.id, context.world_options)
    assert [%{id: "traffic:sol:meridian-01"}] = navigation.contacts
    assert {:ok, response} =
      World.solar_hail(session.id, "traffic:sol:meridian-01", context.world_options)
    assert response.disposition == :neutral
    assert response.cargo == %{"industrial_machinery" => 120}

    assert {:error, :unknown_contact} =
      World.solar_hail(session.id, "fake:freighter", context.world_options)
    assert :ok = World.disconnect(session.id, context.world_options)
    assert {:error, :session_not_found} =
      World.solar_hail(session.id, "traffic:sol:meridian-01", context.world_options)
  end

  test "server-owned course advances ordered waypoints and finishes", context do
    assert {:ok, session} = World.connect(:route_pilot, context.stats, context.world_options)
    opts = context.world_options
    assert {:ok, course} = World.plot_course(session.id, [%{x: 1_032.0, y: 1_000.0}, %{x: 1_064.0, y: 1_000.0}], opts)
    assert course.navigation_mode == :autopilot
    assert course.destination == %{x: 1_032.0, y: 1_000.0}
    assert course.route_waypoints == [%{x: 1_064.0, y: 1_000.0}]

    assert {:ok, step} = World.tick("1-1", opts)
    first = Enum.find(step.entities, &(&1.id == :route_pilot))
    assert first.position == %{x: 1_032.0, y: 1_000.0}
    assert first.destination == %{x: 1_064.0, y: 1_000.0}
    assert first.navigation_mode == :autopilot

    assert {:ok, step} = World.tick("1-1", opts)
    last = Enum.find(step.entities, &(&1.id == :route_pilot))
    assert last.position == %{x: 1_064.0, y: 1_000.0}
    assert last.destination == nil
    assert last.navigation_mode == :manual
    assert last.route_waypoints == []
  end

  test "NPC patrol destinations remain independent of player-only course fields", context do
    assert {:ok, session} = World.connect(:npc_path_guard, context.stats, context.world_options)
    assert {:ok, _course} =
             World.plot_course(session.id, [%{x: 1_096, y: 1_000}], context.world_options)

    # NPC movement and arrival execute in the same tick path as player movement.
    # This regression covers an NPC reaching a patrol destination without
    # attempting to read route_waypoints or navigation_mode from its struct.
    for _tick <- 1..120 do
      assert {:ok, snapshot} = World.tick("1-1", context.world_options)
      assert is_list(snapshot.entities)
    end
  end

  test "manual steering and stop cancel autopilot without client positions", context do
    assert {:ok, session} = World.connect(:route_override, context.stats, context.world_options)
    opts = context.world_options
    route = [%{x: 1_032, y: 1_000}, %{x: 1_064, y: 1_000}]
    assert {:ok, _} = World.plot_course(session.id, route, opts)
    assert {:ok, manual} = World.move(session.id, %{x: 1_000, y: 1_032}, opts)
    assert manual.navigation_mode == :manual
    assert manual.route_waypoints == []
    assert manual.destination == %{x: 1_000, y: 1_032}

    assert {:ok, _} = World.plot_course(session.id, route, opts)
    assert {:error, :session_not_found} = World.stop_navigation(-1, opts)
    assert {:ok, stopped} = World.stop_navigation(session.id, opts)
    assert stopped.position == %{x: 1_000.0, y: 1_000.0}
    assert stopped.destination == nil
    assert stopped.route_waypoints == []
    assert stopped.navigation_mode == :manual

    assert {:ok, snapshot} = World.tick("1-1", opts)
    player = Enum.find(snapshot.entities, &(&1.id == :route_override))
    assert player.position == stopped.position
  end

  test "rejected route preserves the previous active course", context do
    assert {:ok, session} = World.connect(:route_validity, context.stats, context.world_options)
    opts = context.world_options
    assert {:ok, before} = World.plot_course(session.id, [%{x: 1_128, y: 1_000}], opts)
    assert {:error, :outside_map} =
             World.plot_course(session.id, [%{x: 1_200, y: 1_000}, %{x: -1, y: 10}], opts)
    assert {:error, :invalid_course} = World.plot_course(session.id, [], opts)
    assert {:ok, snapshot} = World.snapshot("1-1", opts)
    current = Enum.find(snapshot.entities, &(&1.id == :route_validity))
    assert current.destination == before.destination
    assert current.navigation_mode == :autopilot
  end

  test "authoritative route changes altitude and preserves full 3D position", context do
    assert {:ok, session} = World.connect(:altitude_pilot, context.stats, context.world_options)
    opts = context.world_options

    assert {:ok, command} =
             World.plot_course(session.id, [%{x: 1_000.0, y: 1_000.0, z: 64.0}], opts)

    assert command.destination_3d == %{x: 1_000.0, y: 1_000.0, z: 64.0}
    assert command.position == %{x: 1_000.0, y: 1_000.0}
    assert command.position_3d == %{x: 1_000.0, y: 1_000.0, z: 0.0}

    for _tick <- 1..2 do
      assert {:ok, _snapshot} = World.tick("1-1", opts)
    end

    assert {:ok, snapshot} = World.snapshot("1-1", opts)
    ship = Enum.find(snapshot.entities, &(&1.id == :altitude_pilot))
    assert_in_delta ship.position_3d.z, 64.0, 1.0e-6
    assert ship.destination == nil
    assert ship.navigation_mode == :manual
    assert snapshot.volume == %{altitude_min: -3_000, altitude_max: 3_000}
  end

  test "manual thrust is session bound, moves only on ticks and overrides autopilot", context do
    assert {:ok, session} = World.connect(:flight_pilot, context.stats, context.world_options)
    opts = context.world_options

    assert {:ok, _} = World.plot_course(session.id, [%{x: 1_160, y: 1_000}], opts)
    assert {:error, :session_not_found} =
             World.flight_controls(-1, %{throttle: 1.0}, opts)

    assert {:ok, command} =
             World.flight_controls(session.id,
               %{"throttle" => 0.7, "yaw" => 0.0, "pitch" => 0.0,
                 "roll" => 0.0, "mode" => "cruise"}, opts)

    assert command.destination == nil
    assert command.route_waypoints == []
    assert command.throttle == 0.7
    assert command.flight_mode == :cruise
    assert command.position_3d == %{x: 1000.0, y: 1000.0, z: 0.0}

    assert {:ok, tick} = World.tick("1-1", opts)
    pilot = Enum.find(tick.entities, &(&1.id == :flight_pilot))
    assert pilot.position_3d.y < 1000.0
    assert pilot.velocity.y < 0.0

    assert {:error, :invalid_flight_controls} =
             World.flight_controls(session.id, %{throttle: 999}, opts)
    assert {:ok, current} = World.snapshot("1-1", opts)
    assert Enum.find(current.entities, &(&1.id == :flight_pilot)).throttle == 0.7

    assert {:ok, stopped} = World.stop_navigation(session.id, opts)
    assert stopped.throttle == 0.0
    assert stopped.velocity == %{x: 0.0, y: 0.0, z: 0.0}
  end

  test "validates movement against map boundaries and the owning session", context do
    assert {:ok, session} = World.connect(:pilot_two, context.stats, context.world_options)

    assert {:error, :outside_map} =
             World.move(session.id, %{x: 20_001, y: 1_000}, context.world_options)

    assert {:error, :invalid_destination} =
             World.move(session.id, %{x: "spoofed", y: 1_000}, context.world_options)

    assert {:error, :session_not_found} =
             World.move(-1, %{x: 1_100, y: 1_000}, context.world_options)

    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    player = Enum.find(snapshot.entities, &(&1.kind == :player))
    assert player.position == %{x: 1_000.0, y: 1_000.0}
    assert player.destination == nil
  end

  test "manages one live session per player and releases it on disconnect", context do
    assert {:ok, session} = World.connect(:pilot_three, context.stats, context.world_options)

    assert {:error, :already_connected} =
             World.connect(:pilot_three, context.stats, context.world_options)

    assert :ok = World.disconnect(session.id, context.world_options)
    assert {:error, :session_not_found} = World.disconnect(session.id, context.world_options)
    assert {:ok, replacement} = World.connect(:pilot_three, context.stats, context.world_options)
    refute replacement.id == session.id
  end

  test "returns a controlled error for an unavailable map", context do
    assert {:error, :map_not_found} =
             World.connect(
               :lost_pilot,
               context.stats,
               Keyword.put(context.world_options, :map_id, "9-9")
             )

    assert {:error, :map_not_found} = World.snapshot("9-9", context.world_options)
  end

  test "spawns deterministic NPC identities and advances their AI on ticks", context do
    assert {:ok, session} = World.connect(:npc_observer, context.stats, context.world_options)
    assert {:ok, initial} = World.snapshot("1-1", context.world_options)

    npcs = Enum.filter(initial.entities, &(&1.kind == :npc))

    assert Enum.map(npcs, & &1.id) == ["npc:1-1:dart:1"]
    assert hd(npcs).npc_type_id == "dart"
    assert hd(npcs).display_name == "Dart"
    assert hd(npcs).max_hull == 245

    assert Enum.all?(npcs, &(&1.state == :idle))
    assert Enum.all?(npcs, &(is_binary(&1.id) and &1.id != session.entity_id))

    assert {:ok, tick} = World.tick("1-1", context.world_options)
    first_npc = Enum.find(tick.entities, &(&1.id == "npc:1-1:dart:1"))
    assert first_npc.state == :pursue
    assert first_npc.target_id == :npc_observer
    assert_in_delta first_npc.position.x, 1_459.0, 0.000_001
    assert first_npc.position.y == 1_000.0
  end

  test "reserved NPC identities cannot collide with player entities", context do
    assert {:error, :entity_already_joined} =
             World.connect(
               "npc:1-1:dart:1",
               context.stats,
               context.world_options
             )
  end

  test "authorizes targeting with extended laser range and enforces cooldown", context do
    assert {:ok, session} = World.connect(:combat_pilot, context.stats, context.world_options)
    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    near_npc = Enum.find(snapshot.entities, &(&1.id == "npc:1-1:dart:1"))
    assert Enum.count(snapshot.entities, &(&1.kind == :npc)) == 1

    assert {:error, :session_not_found} =
             World.select_target(-1, near_npc.id, context.world_options)

    assert {:error, :target_not_found} =
             World.select_target(session.id, "npc:1-1:missing", context.world_options)

    assert {:error, :target_not_found} =
             World.select_target(session.id, session.entity_id, context.world_options)

    # The extended-range emitter remains a server-owned player weapon.
    assert {:ok, selection_snapshot} = World.snapshot("1-1", context.world_options)
    pilot = Enum.find(selection_snapshot.entities, &(&1.id == :combat_pilot))
    assert pilot.attack_range == 3_600.0
    assert pilot.next_attack_tick == 0

    assert {:ok, %{target: %{id: near_id}}} =
             World.select_target(session.id, near_npc.id, context.world_options)

    assert near_id == near_npc.id
    assert {:ok, attack} = World.attack(session.id, context.world_options)
    # The starter Sunracer has a Garnet laser (10), which penetrates
    # the Dart's 60%-absorbing shields for 6 shield / 4 hull damage.
    assert attack.damage == 10
    assert attack.shield_damage == 6
    assert attack.hull_damage == 4
    assert attack.destroyed == false
    assert {:error, :weapon_cooldown} = World.attack(session.id, context.world_options)

    assert {:ok, after_attack} = World.snapshot("1-1", context.world_options)
    damaged = Enum.find(after_attack.entities, &(&1.id == near_npc.id))
    assert damaged.shields == 114
    assert damaged.hull == 241
  end

  test "laser hit actually reduces shields at 3,200 game units", context do
    opts = context.world_options
    assert {:ok, session} = World.connect(:long_range_pilot, context.stats, opts)
    npc_id = "npc:1-1:dart:1"

    # Place the existing NPC down the ship's +Y axis, within the new
    # weapon range but well beyond the previous 720-unit cutoff.
    [{pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    :sys.replace_state(pid, fn state ->
      npc = Map.fetch!(state.npcs, npc_id)
      at_distance = %{npc | position: %Core.World.Position{x: 1_000.0, y: 4_200.0}}
      pilot = Map.fetch!(state.entities, :long_range_pilot)
      pilot = %{pilot | orientation: Orientation.from_angles(%{
        yaw: :math.pi(), pitch: 0.0, roll: 0.0
      })}
      %{state | npcs: Map.put(state.npcs, npc_id, at_distance),
                entities: Map.put(state.entities, :long_range_pilot, pilot)}
    end)

    assert {:ok, result} = World.fire_ready_weapon(session.id, opts)
    assert result.hit
    assert result.target_id == npc_id
    assert length(result.beams) == 2
    assert Enum.all?(result.beams, & &1.hit)
    assert result.shield_damage > 0
    assert result.hull_damage > 0
    assert result.next_attack_tick > result.tick

    assert {:ok, state} = World.snapshot("1-1", opts)
    damaged = Enum.find(state.entities, &(&1.id == npc_id))
    assert damaged.shields == 120 - result.shield_damage
    assert damaged.hull == 245 - result.hull_damage
  end

  test "manual Space laser works without target lock and consumes cooldown on a miss", context do
    assert {:error, :session_not_found} =
             World.fire_ready_weapon(-1, context.world_options)
    assert {:ok, session} = World.connect(:manual_gunner, context.stats, context.world_options)

    assert {:ok, shot} = World.fire_ready_weapon(session.id, context.world_options)
    assert shot.attacker_id == :manual_gunner
    assert shot.hit in [true, false]
    assert shot.from == %{x: 1_000.0, y: 1_000.0, z: 0.0}
    assert is_number(shot.to.x) and is_number(shot.to.y) and is_number(shot.to.z)
    assert shot.next_attack_tick > shot.tick

    assert_receive {"1-1", :laser_fired, %{attacker_id: :manual_gunner}}
    assert {:error, :weapon_cooldown} =
             World.fire_ready_weapon(session.id, context.world_options)

    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    pilot = Enum.find(snapshot.entities, &(&1.id == :manual_gunner))
    assert pilot.target_id == nil
    assert pilot.engaged_target_id == nil
    assert pilot.next_attack_tick == shot.next_attack_tick
  end

  test "aligned dual lasers reduce authoritative NPC shields with one cooldown", context do
    assert {:ok, session} = World.connect(:wing_test_pilot, context.stats, context.world_options)
    assert {:ok, initial} = World.snapshot("1-1", context.world_options)
    own = Enum.find(initial.entities, &(&1.id == :wing_test_pilot))

    npcs =
      Enum.filter(initial.entities, fn entity ->
        if entity.kind != :npc do
          false
        else
          dx = entity.position_3d.x - own.position_3d.x
          dy = entity.position_3d.y - own.position_3d.y
          dz = entity.position_3d.z - own.position_3d.z
          distance = :math.sqrt(dx * dx + dy * dy + dz * dz)
          distance > 130.0 and distance < 680.0
        end
      end)

    assert npcs != []
    target = hd(npcs)
    dx = target.position_3d.x - own.position_3d.x
    dy = target.position_3d.y - own.position_3d.y
    dz = target.position_3d.z - own.position_3d.z
    yaw = :math.atan2(dx, -dy)
    pitch = :math.atan2(dz, :math.sqrt(dx * dx + dy * dy))

    # Test-only direct state setup allows us to aim precisely without a
    # keyboard hold/release timing dependency. Public gameplay never accepts
    # client-supplied quaternions or client-selected hit IDs.
    [{map_pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    :sys.replace_state(map_pid, fn state ->
      entity = Map.fetch!(state.entities, :wing_test_pilot)
      entity = %{entity | orientation: Orientation.from_angles(
        %{yaw: yaw, pitch: pitch, roll: 0.0}
      )}
      %{state | entities: Map.put(state.entities, :wing_test_pilot, entity)}
    end)

    assert {:ok, burst} = World.fire_ready_weapon(session.id, context.world_options)
    assert burst.hit
    assert length(burst.beams) == 2
    assert Enum.all?(burst.beams, & &1.hit)
    assert length(burst.hits) == 1
    assert burst.target_id == target.id
    assert burst.damage == context.stats.damage
    assert burst.next_attack_tick > burst.tick
    assert {:error, :weapon_cooldown} =
      World.fire_ready_weapon(session.id, context.world_options)

    assert {:ok, after_fire} = World.snapshot("1-1", context.world_options)
    updated = Enum.find(after_fire.entities, &(&1.id == target.id))
    assert updated.shields < target.shields or updated.hull < target.hull
    assert updated.shields == burst.target.shields
    assert updated.hull == burst.target.hull
  end

  test "selection is distinct from persistent tick-owned combat engagement", context do
    assert {:ok, session} = World.connect(:engaged_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:ok, %{selection: %{target_id: ^npc_id}}} =
             World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, selected} = World.snapshot("1-1", context.world_options)
    selected_player = Enum.find(selected.entities, &(&1.id == :engaged_pilot))
    selected_npc = Enum.find(selected.entities, &(&1.id == npc_id))
    assert selected_player.target_id == npc_id
    assert selected_player.engaged_target_id == nil
    assert selected_npc.shields == 120

    assert {:ok, %{target_id: ^npc_id, changed: true}} =
             World.engage_combat(session.id, context.world_options)

    assert {:ok, engaged} = World.snapshot("1-1", context.world_options)
    engaged_player = Enum.find(engaged.entities, &(&1.id == :engaged_pilot))
    assert engaged_player.engaged_target_id == npc_id
    assert engaged_player.destination == nil

    assert {:ok, first_tick} = World.tick("1-1", context.world_options)
    first_target = Enum.find(first_tick.entities, &(&1.id == npc_id))
    assert first_target.shields == 114
    assert first_target.hull == 241
    assert_receive {"1-1", :laser_fired, %{attacker_id: :engaged_pilot, target_id: ^npc_id}}

    for expected_tick <- 2..7 do
      assert {:ok, %{tick: ^expected_tick}} = World.tick("1-1", context.world_options)
    end

    assert {:ok, cooling_down} = World.snapshot("1-1", context.world_options)
    cooling_target = Enum.find(cooling_down.entities, &(&1.id == npc_id))
    assert cooling_target.shields == 114
    assert cooling_target.hull == 241

    assert {:ok, eighth_tick} = World.tick("1-1", context.world_options)
    eighth_target = Enum.find(eighth_tick.entities, &(&1.id == npc_id))
    assert eighth_target.shields == 108
    assert eighth_target.hull == 237
  end

  test "out-of-range engagement pauses while navigation remains independent", context do
    assert {:ok, session} = World.connect(:mobile_gunner, context.stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    # There is only one Dart. Move it beyond the 3,600-unit player weapon
    # range to test disengaged damage without introducing a second NPC.
    [{pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    :sys.replace_state(pid, fn state ->
      npc = Map.fetch!(state.npcs, npc_id)
      moved = %{npc | position: %Core.World.Position{x: 5_200.0, y: 1_000.0}}
      %{state | npcs: Map.put(state.npcs, npc_id, moved)}
    end)

    assert {:ok, _selection} =
             World.select_target(session.id, npc_id, context.world_options)
    assert {:ok, %{changed: true}} =
             World.engage_combat(session.id, context.world_options)

    assert {:ok, _movement} =
             World.move(session.id, %{x: 1_128.0, y: 1_000.0}, context.world_options)

    assert {:ok, tick} = World.tick("1-1", context.world_options)
    player = Enum.find(tick.entities, &(&1.id == :mobile_gunner))
    untouched = Enum.find(tick.entities, &(&1.id == npc_id))

    assert player.position == %{x: 1_032.0, y: 1_000.0}
    assert player.destination == %{x: 1_128.0, y: 1_000.0}
    assert player.target_id == npc_id
    assert player.engaged_target_id == npc_id
    assert untouched.shields == untouched.max_shields
    assert untouched.hull == untouched.max_hull

    # Returning the same Dart to range resumes laser damage on next tick.
    :sys.replace_state(pid, fn state ->
      npc = Map.fetch!(state.npcs, npc_id)
      moved = %{npc | position: %Core.World.Position{x: 1_280.0, y: 1_000.0},
                     destination: nil}
      %{state | npcs: Map.put(state.npcs, npc_id, moved)}
    end)

    assert {:ok, resumed_tick} = World.tick("1-1", context.world_options)
    resumed = Enum.find(resumed_tick.entities, &(&1.id == npc_id))
    assert resumed.shields < resumed.max_shields
    assert resumed.hull < resumed.max_hull
  end

  test "Ctrl and slot-one semantics share one laser toggle while preserving selection",
       context do
    assert {:ok, session} = World.connect(:toggle_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:error, :session_not_found} =
             World.toggle_laser_fire(-1, context.world_options)

    assert {:error, :no_target} =
             World.toggle_laser_fire(session.id, context.world_options)

    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)

    assert {:ok,
            %{
              active: true,
              action_id: "x1_laser",
              target_id: ^npc_id,
              engaged_target_id: ^npc_id
            }} = World.toggle_laser_fire(session.id, context.world_options)

    assert {:ok,
            %{
              slot: 1,
              status: :deactivated,
              action: %{type: :ammunition, activation_mode: :toggle},
              engagement: %{active: false, target_id: ^npc_id, engaged_target_id: nil}
            }} = World.activate_action(session.id, 1, context.world_options)

    assert {:ok, stopped} = World.snapshot("1-1", context.world_options)
    stopped_player = Enum.find(stopped.entities, &(&1.id == :toggle_pilot))
    assert stopped_player.target_id == npc_id
    assert stopped_player.engaged_target_id == nil

    assert {:ok, %{active: true}} =
             World.toggle_laser_fire(session.id, context.world_options)

    assert {:ok, %{engagement: %{active: false}}} =
             World.activate_action(session.id, 1, context.world_options)

    assert {:ok, %{engagement: %{active: true}}} =
             World.activate_action(session.id, 1, context.world_options)

    assert {:ok, %{target_id: nil}} = World.clear_target(session.id, context.world_options)
    assert {:ok, cleared} = World.snapshot("1-1", context.world_options)
    cleared_player = Enum.find(cleared.entities, &(&1.id == :toggle_pilot))
    assert cleared_player.target_id == nil
    assert cleared_player.engaged_target_id == nil
  end

  test "laser toggles cannot bypass the pulse emitter cooldown", context do
    assert {:ok, session} =
             World.connect(:cooldown_toggle_pilot, context.stats, context.world_options)

    npc_id = "npc:1-1:dart:1"

    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)
    assert {:ok, %{active: true}} = World.toggle_laser_fire(session.id, context.world_options)
    assert {:ok, first_tick} = World.tick("1-1", context.world_options)
    first_target = Enum.find(first_tick.entities, &(&1.id == npc_id))
    first_player = Enum.find(first_tick.entities, &(&1.id == :cooldown_toggle_pilot))
    assert first_player.next_attack_tick == 8

    assert {:ok, %{active: false}} = World.toggle_laser_fire(session.id, context.world_options)
    assert {:ok, %{active: true}} = World.toggle_laser_fire(session.id, context.world_options)

    for expected_tick <- 2..7 do
      assert {:ok, snapshot} = World.tick("1-1", context.world_options)
      assert snapshot.tick == expected_tick
      target = Enum.find(snapshot.entities, &(&1.id == npc_id))
      player = Enum.find(snapshot.entities, &(&1.id == :cooldown_toggle_pilot))
      assert target.shields == first_target.shields
      assert target.hull == first_target.hull
      assert player.next_attack_tick == 8
    end

    assert {:ok, eighth_tick} = World.tick("1-1", context.world_options)
    eighth_target = Enum.find(eighth_tick.entities, &(&1.id == npc_id))
    assert eighth_target.shields < first_target.shields
    assert eighth_target.hull < first_target.hull
  end

  test "destroying the only Dart permits a fresh toggle after respawn", context do
    lethal_stats = %{context.stats | damage: 1_200}
    assert {:ok, session} = World.connect(:sequential_hunter, lethal_stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:ok, _selection} =
             World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, %{active: true}} = World.toggle_laser_fire(session.id, context.world_options)
    assert {:ok, destroyed_tick} = World.tick("1-1", context.world_options)
    destroyed_player = Enum.find(destroyed_tick.entities, &(&1.id == :sequential_hunter))
    assert destroyed_player.target_id == nil
    assert destroyed_player.engaged_target_id == nil
    refute Enum.any?(destroyed_tick.entities, &(&1.id == npc_id))
    assert {:error, :target_not_found} =
             World.select_target(session.id, npc_id, context.world_options)

    for tick <- 2..31 do
      assert {:ok, %{tick: ^tick}} = World.tick("1-1", context.world_options)
    end
    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    assert Enum.count(snapshot.entities, &(&1.kind == :npc)) == 1

    assert {:ok, _selection} =
             World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, %{active: true, target_id: ^npc_id}} =
             World.toggle_laser_fire(session.id, context.world_options)

    assert {:ok, next_engagement} = World.snapshot("1-1", context.world_options)
    next_player = Enum.find(next_engagement.entities, &(&1.id == :sequential_hunter))
    assert next_player.target_id == npc_id
    assert next_player.engaged_target_id == npc_id
  end

  test "repeated engagement, empty actions, invalid actions, and cancellation are safe",
       context do
    assert {:ok, session} = World.connect(:action_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:ok, %{slot: 2, status: :empty, action: nil}} =
             World.activate_action(session.id, 2, context.world_options)

    assert {:error, :invalid_action_slot} =
             World.activate_action(session.id, 0, context.world_options)

    assert {:error, :no_target} = World.engage_combat(session.id, context.world_options)
    assert {:error, :no_target} = World.activate_action(session.id, 1, context.world_options)
    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, %{slot: 1, status: :activated, engagement: %{changed: true}}} =
             World.activate_action(session.id, 1, context.world_options)

    assert {:ok, %{changed: false}} = World.engage_combat(session.id, context.world_options)

    assert {:ok, _movement} =
             World.move(session.id, %{x: 1_064.0, y: 1_000.0}, context.world_options)

    assert {:ok, %{reason: :cancelled, previous_target_id: ^npc_id}} =
             World.disengage_combat(session.id, context.world_options)

    assert {:ok, cancelled} = World.snapshot("1-1", context.world_options)
    player = Enum.find(cancelled.entities, &(&1.id == :action_pilot))
    assert player.target_id == nil
    assert player.engaged_target_id == nil
    assert player.destination == %{x: 1_064.0, y: 1_000.0}
  end

  test "automatic destruction clears engagement and respawn does not inherit target lock",
       context do
    lethal_stats = %{context.stats | damage: 1_200}
    assert {:ok, session} = World.connect(:automatic_hunter, lethal_stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)
    assert {:ok, _engagement} = World.engage_combat(session.id, context.world_options)
    assert {:ok, destroyed_tick} = World.tick("1-1", context.world_options)

    player = Enum.find(destroyed_tick.entities, &(&1.id == :automatic_hunter))
    assert player.target_id == nil
    assert player.engaged_target_id == nil
    refute Enum.any?(destroyed_tick.entities, &(&1.id == npc_id))

    assert_receive {"1-1", :combat_disengaged,
                    %{player_id: :automatic_hunter, reason: :target_destroyed}}

    for expected_tick <- 2..31 do
      assert {:ok, %{tick: ^expected_tick}} = World.tick("1-1", context.world_options)
    end

    assert {:ok, respawned} = World.snapshot("1-1", context.world_options)
    respawned_player = Enum.find(respawned.entities, &(&1.id == :automatic_hunter))
    respawned_npc = Enum.find(respawned.entities, &(&1.id == npc_id))
    assert respawned_player.target_id == nil
    assert respawned_player.engaged_target_id == nil
    assert respawned_npc.status == :alive
  end

  test "destroys, removes, and respawns an NPC on deterministic ticks", context do
    lethal_stats = %{context.stats | damage: 1_200}
    assert {:ok, session} = World.connect(:npc_hunter, lethal_stats, context.world_options)
    npc_id = "npc:1-1:dart:1"

    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, %{destroyed: true, respawn_tick: 30}} =
             World.attack(session.id, context.world_options)

    assert_receive {"1-1", :laser_fired, %{target_id: ^npc_id, destroyed: true}}

    assert_receive {"1-1", :entity_destroyed,
                    %{entity: %{id: ^npc_id, status: :destroyed}, respawn_tick: 30}}

    assert {:ok, destroyed_snapshot} = World.snapshot("1-1", context.world_options)
    refute Enum.any?(destroyed_snapshot.entities, &(&1.id == npc_id))

    for expected_tick <- 1..30 do
      assert {:ok, %{tick: ^expected_tick}} = World.tick("1-1", context.world_options)
    end

    assert_receive {"1-1", :npc_spawned, %{id: ^npc_id, hull: 245, shields: 120, state: :idle}}

    assert {:ok, respawned_snapshot} = World.snapshot("1-1", context.world_options)
    respawned = Enum.find(respawned_snapshot.entities, &(&1.id == npc_id))
    assert respawned.position == %{x: 1_480.0, y: 1_000.0}
    assert respawned.hull == respawned.max_hull
    assert respawned.shields == respawned.max_shields
  end

  test "serializes concurrent and repeated attack attempts", context do
    assert {:ok, session} = World.connect(:rapid_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:dart:1"
    assert {:ok, _selection} = World.select_target(session.id, npc_id, context.world_options)

    results =
      1..2
      |> Task.async_stream(
        fn _attempt -> World.attack(session.id, context.world_options) end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _attack}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :weapon_cooldown})) == 1
  end

  test "disconnecting a pursued player clears NPC combat state", context do
    assert {:ok, session} = World.connect(:departing_pilot, context.stats, context.world_options)
    assert {:ok, _tick} = World.tick("1-1", context.world_options)
    assert {:ok, pursuing_snapshot} = World.snapshot("1-1", context.world_options)

    assert Enum.any?(
             pursuing_snapshot.entities,
             &(&1.kind == :npc and &1.target_id == :departing_pilot)
           )

    assert {:ok, _selection} =
             World.select_target(
               session.id,
               "npc:1-1:dart:1",
               context.world_options
             )

    assert {:ok, _engagement} = World.engage_combat(session.id, context.world_options)

    assert :ok = World.disconnect(session.id, context.world_options)
    assert {:error, :session_not_found} = World.attack(session.id, context.world_options)
    assert {:ok, after_disconnect} = World.snapshot("1-1", context.world_options)
    refute Enum.any?(after_disconnect.entities, &(&1.kind == :player))

    assert Enum.all?(
             Enum.filter(after_disconnect.entities, &(&1.kind == :npc)),
             &is_nil(&1.target_id)
           )
  end

  test "a destroyed player cannot move or attack", context do
    fragile_stats = %{context.stats | hit_points: 10}
    assert {:ok, session} = World.connect(:fragile_pilot, fragile_stats, context.world_options)

    assert {:ok, _selection} =
             World.select_target(
               session.id,
               "npc:1-1:dart:1",
               context.world_options
             )

    assert {:ok, _engagement} = World.engage_combat(session.id, context.world_options)

    for _tick <- 1..5 do
      assert {:ok, _snapshot} = World.tick("1-1", context.world_options)
    end

    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    player = Enum.find(snapshot.entities, &(&1.id == :fragile_pilot))
    assert player.status == :destroyed
    assert player.hull == 0
    assert player.target_id == nil
    assert player.engaged_target_id == nil

    assert Enum.all?(
             Enum.filter(snapshot.entities, &(&1.kind == :npc)),
             &(&1.target_id != :fragile_pilot)
           )

    assert {:error, :attacker_destroyed} = World.attack(session.id, context.world_options)

    assert {:error, :attacker_destroyed} =
             World.toggle_laser_fire(session.id, context.world_options)

    assert {:error, :attacker_destroyed} =
             World.activate_action(session.id, 1, context.world_options)

    assert {:error, :attacker_destroyed} =
             World.move(session.id, %{x: 1_100, y: 1_000}, context.world_options)
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a neutral trader can be attacked and retaliates only after a real hit", context do
    opts = context.world_options
    stats = %{context.stats | damage: 50}
    assert {:ok, session} = World.connect(9_735, stats, opts)

    # Vesper-02 is a normally neutral scheduled courier. The same policy
    # also applies to server-generated independent traders such as Harbor-1.
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))

    assert {:ok, held} = World.solar_snapshot(session.id, opts)
    assert %{id: encounter_id, classification: :neutral_flyby} =
      held.pending_encounter
    assert {:ok, %{navigation: combat, enemy: enemy}} =
      World.solar_enter_tactical(session.id, encounter_id, opts)
    assert combat.tactical_encounter.classification == :neutral_flyby
    assert combat.cruise_paused
    assert enemy.display_name == held.pending_encounter.call_sign
    assert enemy.npc_type_id == "solar-scow-9735"
    assert enemy.ship_class == "scow"
    assert enemy.state == :cruise
    assert enemy.destination_3d != nil
    assert %{origin_id: "earth", destination_id: "venus"} =
      combat.tactical_encounter.course |> Map.take([:origin_id, :destination_id])
    # The current courier on Earth -> Venus has its own independent
    # outbound course. The tactical Scow must use that, not our own route.
    assert %{origin_id: "earth", destination_id: "venus"} = enemy.course
    assert enemy.max_hull == 210
    assert enemy.damage == 10
    assert enemy.speed == 105

    [{map_pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    assert :sys.get_state(map_pid).solar_tactical[session.entity_id].provoked? == false

    # A neutral ship must not lock or shoot the owner merely because the
    # pilot selected Attack; it can defend itself after the first hit.
    assert {:ok, before} = World.tick("1-1", opts)
    idle_enemy = Enum.find(before.entities, &(&1.id == enemy.id))
    assert idle_enemy.target_id == nil
    assert {:ok, _} = World.select_target(session.id, enemy.id, opts)
    assert {:ok, %{destroyed: false, target_id: target_id}} =
      World.attack(session.id, opts)
    assert target_id == enemy.id
    assert :sys.get_state(map_pid).solar_tactical[session.entity_id].provoked? == true

    assert {:ok, after_hit} = World.tick("1-1", opts)
    defending = Enum.find(after_hit.entities, &(&1.id == enemy.id))
    assert defending.target_id == session.entity_id

    # Retiring the encounter must release the original cruise without
    # accidentally retaining the NPC's aggression in future voyages.
    assert {:ok, resumed} =
      World.solar_finish_tactical(session.id, encounter_id, :retreat, opts)
    assert resumed.tactical_encounter == nil
    refute resumed.cruise_paused
    assert :sys.get_state(map_pid).solar_tactical == %{}

    # Damage belongs to the original shared traffic vessel, not the
    # temporary NPC that was removed on retreat.
    real_contact_id = held.pending_encounter.contact_id
    survivor = :sys.get_state(@solar_navigation_server).traffic[real_contact_id]
    assert survivor.combat.hull == defending.hull
    assert survivor.combat.shields == defending.shields
    assert survivor.state == :in_transit
    assert survivor.cargo == %{"medical_supplies" => 48}
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a merchant evades injury, then offers surrender rather than fighting to destruction",
       context do
    opts = context.world_options
    stats = %{context.stats | damage: 10}
    {:ok, session} = World.connect(9_737, stats, opts)
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id

    assert {:ok, %{enemy: enemy}} =
      World.solar_enter_tactical(session.id, encounter_id, opts)
    assert enemy.ship_class == "scow"

    assert {:error, :enemy_not_surrendered} =
      World.solar_finish_tactical(session.id, encounter_id, :surrender, opts)

    [{pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    assert {:ok, _} = World.select_target(session.id, enemy.id, opts)
    :sys.replace_state(pid, fn map ->
      npc = Map.fetch!(map.npcs, enemy.id)
      updated = %{npc | hull: 170, shields: 0}
      %{map | npcs: Map.put(map.npcs, enemy.id, updated)}
    end)

    assert {:ok, %{destroyed: false}} = World.attack(session.id, opts)
    fleeing = :sys.get_state(pid).npcs[enemy.id]
    assert fleeing.state == :evade
    assert fleeing.speed > 105
    assert fleeing.destination != nil
    assert fleeing.hull == 160

    for _ <- 1..8, do: assert({:ok, _} = World.tick("1-1", opts))
    :sys.replace_state(pid, fn map ->
      npc = Map.fetch!(map.npcs, enemy.id)
      %{map | npcs: Map.put(map.npcs, enemy.id, %{npc | hull: 78})}
    end)

    assert {:ok, %{destroyed: false}} = World.attack(session.id, opts)
    surrendered = :sys.get_state(pid).npcs[enemy.id]
    assert surrendered.state == :surrendered
    assert surrendered.hull == 68
    assert surrendered.destination == nil
    assert {:error, :invalid_target} = World.attack(session.id, opts)

    assert {:ok, resumed} =
      World.solar_finish_tactical(session.id, encounter_id, :surrender, opts)
    assert resumed.tactical_encounter == nil
    refute resumed.cruise_paused
    refute Map.has_key?(:sys.get_state(pid).npcs, enemy.id)

    # A surrender must leave the same cargo with the same disabled vessel.
    contact = :sys.get_state(@solar_navigation_server).traffic[held.pending_encounter.contact_id]
    assert contact.combat == %{hull: 68, max_hull: 210, shields: 0,
                               max_shields: 45, status: :surrendered}
    assert contact.state == :disabled
    assert contact.cargo == %{"medical_supplies" => 48}
    assert :ok = SolarNavigation.tick(@solar_navigation_server)
    assert :sys.get_state(@solar_navigation_server).traffic[contact.id].position_km ==
      contact.position_km
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a merchant Scow travels its existing course, leaves the encounter, and unpauses SOL",
       context do
    opts = context.world_options
    {:ok, session} = World.connect(9_736, context.stats, opts)
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id
    assert {:ok, %{enemy: enemy}} = World.solar_enter_tactical(session.id, encounter_id, opts)

    [{map_pid, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    assert enemy.state == :cruise
    assert %{origin_id: "earth", destination_id: "venus"} = enemy.course
    assert %{x: _, y: _, z: _} = enemy.destination_3d
    initial = enemy.position_3d

    assert {:ok, first} = World.tick("1-1", opts)
    moved = Enum.find(first.entities, &(&1.id == enemy.id))
    assert moved.state == :cruise
    assert moved.course == enemy.course
    assert moved.destination_3d == enemy.destination_3d
    assert moved.angle == enemy.angle
    assert moved.position_3d != initial

    assert {:ok, _} = World.select_target(session.id, enemy.id, opts)

    # Put the server-owned NPC near the end of its registered lane; the
    # next deterministic world tick finishes it without 600 idle ticks.
    :sys.replace_state(map_pid, fn map ->
      scow = Map.fetch!(map.npcs, enemy.id)
      %{heading: heading} = scow.course
      near_end = %Core.World.Position{
        x: scow.destination.x - heading.x * 2.0,
        y: scow.destination.y - heading.y * 2.0,
        z: scow.destination.z
      }
      %{map | npcs: Map.put(map.npcs, enemy.id,
        %{scow | position: near_end})}
    end)

    assert {:ok, after_pass} = World.tick("1-1", opts)
    refute Enum.any?(after_pass.entities, &(&1.id == enemy.id))
    pilot = Enum.find(after_pass.entities, &(&1.id == session.entity_id))
    assert pilot.target_id == nil
    assert :sys.get_state(map_pid).solar_tactical == %{}

    assert {:ok, resumed} = World.solar_snapshot(session.id, opts)
    refute resumed.cruise_paused
    assert resumed.tactical_encounter == nil
    assert resumed.pending_encounter == nil
    assert resumed.elapsed_ms == held.elapsed_ms
    contact = :sys.get_state(@solar_navigation_server).traffic[held.pending_encounter.contact_id]
    assert contact.combat.hull == enemy.hull
    assert contact.combat.shields == enemy.shields
    assert contact.state == :in_transit

    assert :ok = SolarNavigation.tick(@solar_navigation_server)
    assert {:ok, moving} = World.solar_snapshot(session.id, opts)
    assert moving.elapsed_ms == held.elapsed_ms + 1_000
    assert {:error, :no_tactical_encounter} =
      World.solar_finish_tactical(session.id, encounter_id, :victory, opts)
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a held hostile SOL encounter enters map-owned 3D combat and resumes on victory",
       context do
    opts = context.world_options
    stats = %{context.stats | damage: 1_200}
    {:ok, session} = World.connect(9_731, stats, opts)

    :sys.replace_state(@solar_navigation_server, fn state ->
      hostile = Map.update!(state.traffic, "traffic:sol:vesper-02",
        &%{&1 | disposition: :hostile})
      %{state | traffic: hostile}
    end)

    assert {:ok, %{status: :traveling}} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    assert {:ok, held} = World.solar_snapshot(session.id, opts)
    assert held.cruise_paused
    assert %{id: encounter_id, classification: :hostile_contact} = held.pending_encounter

    assert {:error, :interplanetary_cruise_active} = World.attack(session.id, opts)
    assert {:error, :encounter_mismatch} =
      World.solar_enter_tactical(session.id, "forged-contact", opts)

    assert {:ok, %{navigation: combat, enemy: enemy}} =
      World.solar_enter_tactical(session.id, encounter_id, opts)
    assert combat.tactical_encounter.id == encounter_id
    assert combat.cruise_paused
    assert enemy.display_name == held.pending_encounter.call_sign
    assert enemy.kind == :npc
    # Vesper-02 is a courier, so it remains a Scow even when hostile.
    assert enemy.npc_type_id == "solar-scow-9731"
    assert enemy.ship_class == "scow"
    # The cockpit shows the physical current planetary region during combat;
    # the distant destination preview would conceal actual collision geometry.
    assert combat.planetary_view.body_id == "earth"
    assert combat.planetary_view.stage == :orbital_preview
    assert :ok = SolarNavigation.tick(@solar_navigation_server)
    assert {:ok, frozen} = World.solar_snapshot(session.id, opts)
    assert frozen.elapsed_ms == held.elapsed_ms
    assert {:error, :enemy_still_active} =
      World.solar_finish_tactical(session.id, encounter_id, :victory, opts)
    assert {:error, :tactical_encounter_active} =
      World.solar_resolve_encounter(session.id, encounter_id, :continue, opts)

    assert {:ok, other} = World.connect(9_732, context.stats, opts)
    assert {:error, :no_pending_encounter} =
      World.solar_enter_tactical(other.id, encounter_id, opts)

    assert {:ok, _lock} = World.select_target(session.id, enemy.id, opts)
    assert {:ok, %{destroyed: true}} = World.attack(session.id, opts)
    assert {:ok, resumed} =
      World.solar_finish_tactical(session.id, encounter_id, :victory, opts)
    assert resumed.status == :traveling
    refute resumed.cruise_paused
    assert resumed.tactical_encounter == nil
    assert resumed.pending_encounter == nil
    assert {:ok, map} = World.snapshot("1-1", opts)
    refute Enum.any?(map.entities, &(&1.id == enemy.id))
    destroyed_contact =
      :sys.get_state(@solar_navigation_server).traffic[held.pending_encounter.contact_id]
    assert destroyed_contact.state == :destroyed
    assert destroyed_contact.combat.hull == 0
    assert destroyed_contact.combat.status == :destroyed
    assert destroyed_contact.cargo == %{"medical_supplies" => 48}

    assert :ok = SolarNavigation.tick(@solar_navigation_server)
    assert {:ok, moving} = World.solar_snapshot(session.id, opts)
    assert moving.elapsed_ms == held.elapsed_ms + 1_000
    assert {:error, :no_tactical_encounter} =
      World.solar_finish_tactical(session.id, encounter_id, :victory, opts)
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "retreat removes only this pilot's encounter NPC and preserves SOL progress", context do
    opts = context.world_options
    {:ok, session} = World.connect(9_733, context.stats, opts)

    :sys.replace_state(@solar_navigation_server, fn state ->
      hostile = Map.update!(state.traffic, "traffic:sol:vesper-02",
        &%{&1 | disposition: :hostile})
      %{state | traffic: hostile}
    end)

    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id
    assert {:ok, %{enemy: enemy}} =
      World.solar_enter_tactical(session.id, encounter_id, opts)
    assert {:error, :encounter_mismatch} =
      World.solar_finish_tactical(session.id, "other", :retreat, opts)
    assert {:ok, resumed} =
      World.solar_finish_tactical(session.id, encounter_id, :retreat, opts)
    assert resumed.elapsed_ms == held.elapsed_ms
    assert resumed.pending_encounter == nil
    assert resumed.tactical_encounter == nil
    assert {:ok, map} = World.snapshot("1-1", opts)
    refute Enum.any?(map.entities, &(&1.id == enemy.id))
  end


  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a defeated pilot cannot forge survival and does not retain a stuck SOL hold",
       context do
    opts = context.world_options
    {:ok, session} = World.connect(9_734, context.stats, opts)

    :sys.replace_state(@solar_navigation_server, fn state ->
      hostile = Map.update!(state.traffic, "traffic:sol:vesper-02",
        &%{&1 | disposition: :hostile})
      %{state | traffic: hostile}
    end)

    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id

    assert {:ok, %{enemy: enemy}} =
      World.solar_enter_tactical(session.id, encounter_id, opts)
    assert {:error, :pilot_still_alive} =
      World.solar_finish_tactical(session.id, encounter_id, :defeat, opts)

    [{map_server, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    :sys.replace_state(map_server, fn state ->
      player = Map.fetch!(state.entities, session.entity_id)
      destroyed = %{player | status: :destroyed, hull: 0}
      %{state | entities: Map.put(state.entities, session.entity_id, destroyed)}
    end)

    assert {:ok, canceled} =
      World.solar_finish_tactical(session.id, encounter_id, :defeat, opts)
    assert canceled.status == :idle
    assert canceled.location_id == "earth"
    assert canceled.pending_encounter == nil
    assert canceled.tactical_encounter == nil
    assert {:ok, map} = World.snapshot("1-1", opts)
    refute Enum.any?(map.entities, &(&1.id == enemy.id))
    assert {:error, :attacker_destroyed} = World.attack(session.id, opts)
  end


  @tag no_initial_encounter: true, no_auto_respawn: true
  test "a previously damaged real courier enters tactical combat without repairing",
       context do
    opts = context.world_options
    {:ok, session} = World.connect(9_738, context.stats, opts)

    # Simulate a previously settled injury on the actual SOL traffic entry.
    :sys.replace_state(@solar_navigation_server, fn state ->
      traffic = Map.update!(state.traffic, "traffic:sol:vesper-02", fn ship ->
        %{ship | combat: %{ship.combat | hull: 125, shields: 11}}
      end)
      %{state | traffic: traffic}
    end)

    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)

    assert {:ok, %{enemy: enemy, navigation: active}} =
      World.solar_enter_tactical(session.id, held.pending_encounter.id, opts)
    assert active.tactical_encounter.contact_id == "traffic:sol:vesper-02"
    assert active.tactical_encounter.voyage_number == 1
    assert enemy.hull == 125
    assert enemy.max_hull == 210
    assert enemy.shields == 11
    assert enemy.max_shields == 45

    assert {:ok, _} = World.solar_finish_tactical(
      session.id, held.pending_encounter.id, :retreat, opts)
    actual = :sys.get_state(@solar_navigation_server).traffic["traffic:sol:vesper-02"]
    assert actual.combat.hull == 125
    assert actual.combat.shields == 11
    assert actual.state == :in_transit
  end


  @tag no_initial_encounter: true, no_auto_respawn: true
  test "physical IDs and damaged hull survive the strategic-tactical handoff", context do
    {:ok, full} = Core.Ships.Condition.initial(context.stats)
    damaged = %{full | hull: full.hull - 1, shields: 0}
    opts = Keyword.merge(context.world_options,
      ship_instance_id: 42_001, combat_condition: damaged)
    {:ok, session} = World.connect(9_741, context.stats, opts)

    assert {:ok, %{ship_instance_id: 42_001, combat: ^damaged}} =
             World.ship_condition(session.id, opts)
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id

    assert {:ok, %{enemy: enemy}} = World.solar_enter_tactical(session.id, encounter_id, opts)
    assert enemy.strategic_vessel_id == held.pending_encounter.contact_id
    assert {:ok, %{tactical_encounter: nil}} =
             World.solar_finish_tactical(session.id, encounter_id, :retreat, opts)
    assert {:ok, %{ship_instance_id: 42_001, combat: ^damaged}} =
             World.ship_condition(session.id, opts)
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "failed persistence retains tactical evidence and exclusive vessel claim", context do
    opts = context.world_options
    {:ok, session} = World.connect(9_742, context.stats, opts)
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id

    assert {:ok, %{enemy: enemy}} = World.solar_enter_tactical(session.id, encounter_id, opts)
    assert {:error, :tactical_encounter_active} = World.disconnect(session.id, opts)

    failing = Keyword.put(opts, :persist_player_condition,
      fn _ -> {:error, :storage_unavailable} end)
    assert {:error, :storage_unavailable} =
             World.solar_finish_tactical(session.id, encounter_id, :retreat, failing)

    [{map_server, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    pending = :sys.get_state(map_server).solar_tactical[session.entity_id]
    # Both combatants are frozen until the map, DB and SOL owners agree.
    assert {:error, :entity_not_found} =
             World.move(session.id, %{x: 1_100, y: 1_100}, opts)
    assert {:ok, %{combat: _frozen_condition}} =
             World.ship_condition(session.id, opts)
    assert pending.prepared.outcome == :retreat
    assert pending.prepared.report.npc.contact_id == enemy.strategic_vessel_id
    assert :sys.get_state(@solar_navigation_server).tactical_claims != %{}
    assert {:error, :tactical_settlement_conflict} =
             World.solar_finish_tactical(session.id, encounter_id, :surrender, opts)

    assert {:ok, %{tactical_encounter: nil}} =
             World.solar_finish_tactical(session.id, encounter_id, :retreat, opts)
    assert :sys.get_state(map_server).solar_tactical == %{}
    assert :sys.get_state(@solar_navigation_server).tactical_claims == %{}
    assert {:ok, %{combat: _restored_condition}} =
             World.ship_condition(session.id, opts)
    assert :ok = World.disconnect(session.id, opts)
  end

  @tag no_initial_encounter: true, no_auto_respawn: true
  test "strategic settlement is idempotent if tactical map cleanup is delayed", context do
    opts = context.world_options
    {:ok, session} = World.connect(9_743, context.stats, opts)
    assert {:ok, _} = World.solar_set_course(session.id, "venus", opts)
    for _ <- 1..85, do: assert(:ok = SolarNavigation.tick(@solar_navigation_server))
    {:ok, held} = World.solar_snapshot(session.id, opts)
    encounter_id = held.pending_encounter.id

    assert {:ok, _} = World.solar_enter_tactical(session.id, encounter_id, opts)
    assert {:ok, verified} = Core.World.MapServer.prepare_solar_tactical(
      @registry, "1-1", session.id, session.entity_id, encounter_id, :retreat)
    assert {:ok, %{tactical_encounter: nil}} =
             SolarNavigation.finish_tactical(@solar_navigation_server, session.entity_id,
               encounter_id, :retreat, verified.npc)

    assert {:ok, %{tactical_encounter: nil}} =
             World.solar_finish_tactical(session.id, encounter_id, :retreat, opts)
    [{map_server, _}] = Registry.lookup(@registry, {:world_map, "1-1"})
    assert :sys.get_state(map_server).solar_tactical == %{}
    assert :sys.get_state(@solar_navigation_server).tactical_claims == %{}
  end



  @tag no_initial_encounter: true
  test "prepared disconnect detaches and freezes an entity until durable save succeeds", context do
    opts = context.world_options
    {:ok, session} = World.connect(:departing_ship, context.stats, opts)
    assert {:ok, %{combat: initial}} = World.prepare_disconnect(session.id, opts)
    assert {:ok, true} = World.pending_disconnect?(session.id, opts)
    assert {:ok, %{combat: ^initial}} = World.prepare_disconnect(session.id, opts)
    assert {:error, :entity_not_found} =
             World.move(session.id, %{x: 1_100, y: 1_100}, opts)

    assert {:ok, snapshot} = World.snapshot("1-1", opts)
    refute Enum.any?(snapshot.entities, &(&1.id == :departing_ship))
    assert :ok = World.disconnect(session.id, opts)
    assert {:error, :session_not_found} = World.prepare_disconnect(session.id, opts)
  end


end
