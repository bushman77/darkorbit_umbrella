defmodule Core.WorldTest do
  use ExUnit.Case

  alias Core.Ships.Stats
  alias Core.World
  alias Core.World.MapDefinition
  alias Core.World.Supervisor, as: WorldSupervisor

  @registry Core.WorldTest.Registry
  @sessions Core.WorldTest.Sessions
  @supervisor Core.WorldTest.Supervisor

  setup do
    test_process = self()
    event_sink = fn map_id, event, payload -> send(test_process, {map_id, event, payload}) end

    start_supervised!(
      {WorldSupervisor,
       name: @supervisor,
       registry: @registry,
       sessions: @sessions,
       maps: [MapDefinition.starting_map()],
       tick_ms: 100,
       auto_tick: false,
       event_sink: event_sink}
    )

    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    %{stats: stats, world_options: [registry: @registry, sessions: @sessions]}
  end

  test "headless simulation moves a ship across the map on deterministic ticks", context do
    assert {:ok, session} = World.connect(:pilot_one, context.stats, context.world_options)
    assert_receive {"1-1", :entity_joined, %{player_id: :pilot_one}}

    assert {:ok, initial} = World.snapshot("1-1", context.world_options)
    assert initial.tick == 0
    assert initial.tick_ms == 100
    player = Enum.find(initial.entities, &(&1.kind == :player))
    assert player.position == %{x: 1_000.0, y: 1_000.0}
    assert Enum.count(initial.entities, &(&1.kind == :npc)) == 3

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

    assert Enum.map(npcs, & &1.id) == [
             "npc:1-1:rift_skirmisher:1",
             "npc:1-1:rift_skirmisher:2",
             "npc:1-1:rift_skirmisher:3"
           ]

    assert Enum.all?(npcs, &(&1.state == :idle))
    assert Enum.all?(npcs, &(is_binary(&1.id) and &1.id != session.entity_id))

    assert {:ok, tick} = World.tick("1-1", context.world_options)
    first_npc = Enum.find(tick.entities, &(&1.id == "npc:1-1:rift_skirmisher:1"))
    assert first_npc.state == :pursue
    assert first_npc.target_id == :npc_observer
    assert_in_delta first_npc.position.x, 1_462.5, 0.000_001
    assert first_npc.position.y == 1_000.0
  end

  test "reserved NPC identities cannot collide with player entities", context do
    assert {:error, :entity_already_joined} =
             World.connect(
               "npc:1-1:rift_skirmisher:1",
               context.stats,
               context.world_options
             )
  end

  test "authorizes targeting and enforces range and cooldown", context do
    assert {:ok, session} = World.connect(:combat_pilot, context.stats, context.world_options)
    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    near_npc = Enum.find(snapshot.entities, &(&1.id == "npc:1-1:rift_skirmisher:1"))
    far_npc = Enum.find(snapshot.entities, &(&1.id == "npc:1-1:rift_skirmisher:2"))

    assert {:error, :session_not_found} =
             World.select_target(-1, near_npc.id, context.world_options)

    assert {:error, :target_not_found} =
             World.select_target(session.id, "npc:1-1:missing", context.world_options)

    assert {:error, :target_not_found} =
             World.select_target(session.id, session.entity_id, context.world_options)

    assert {:ok, %{target: %{id: far_id}}} =
             World.select_target(session.id, far_npc.id, context.world_options)

    assert far_id == far_npc.id
    assert {:error, :out_of_range} = World.attack(session.id, context.world_options)

    assert {:ok, %{target: %{id: near_id}}} =
             World.select_target(session.id, near_npc.id, context.world_options)

    assert near_id == near_npc.id
    assert {:ok, attack} = World.attack(session.id, context.world_options)
    assert attack.damage == 40
    assert attack.shield_damage == 24
    assert attack.hull_damage == 16
    assert attack.destroyed == false
    assert {:error, :weapon_cooldown} = World.attack(session.id, context.world_options)

    assert {:ok, after_attack} = World.snapshot("1-1", context.world_options)
    damaged = Enum.find(after_attack.entities, &(&1.id == near_npc.id))
    assert damaged.shields == 376
    assert damaged.hull == 784
  end

  test "selection is distinct from persistent tick-owned combat engagement", context do
    assert {:ok, session} = World.connect(:engaged_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:rift_skirmisher:1"

    assert {:ok, %{selection: %{target_id: ^npc_id}}} =
             World.select_target(session.id, npc_id, context.world_options)

    assert {:ok, selected} = World.snapshot("1-1", context.world_options)
    selected_player = Enum.find(selected.entities, &(&1.id == :engaged_pilot))
    selected_npc = Enum.find(selected.entities, &(&1.id == npc_id))
    assert selected_player.target_id == npc_id
    assert selected_player.engaged_target_id == nil
    assert selected_npc.shields == 400

    assert {:ok, %{target_id: ^npc_id, changed: true}} =
             World.engage_combat(session.id, context.world_options)

    assert {:ok, engaged} = World.snapshot("1-1", context.world_options)
    engaged_player = Enum.find(engaged.entities, &(&1.id == :engaged_pilot))
    assert engaged_player.engaged_target_id == npc_id
    assert engaged_player.destination == nil

    assert {:ok, first_tick} = World.tick("1-1", context.world_options)
    first_target = Enum.find(first_tick.entities, &(&1.id == npc_id))
    assert first_target.shields == 376
    assert first_target.hull == 784
    assert_receive {"1-1", :laser_fired, %{attacker_id: :engaged_pilot, target_id: ^npc_id}}

    for expected_tick <- 2..7 do
      assert {:ok, %{tick: ^expected_tick}} = World.tick("1-1", context.world_options)
    end

    assert {:ok, cooling_down} = World.snapshot("1-1", context.world_options)
    cooling_target = Enum.find(cooling_down.entities, &(&1.id == npc_id))
    assert cooling_target.shields == 376
    assert cooling_target.hull == 784

    assert {:ok, eighth_tick} = World.tick("1-1", context.world_options)
    eighth_target = Enum.find(eighth_tick.entities, &(&1.id == npc_id))
    assert eighth_target.shields == 352
    assert eighth_target.hull == 768
  end

  test "out-of-range engagement pauses while navigation remains independent", context do
    assert {:ok, session} = World.connect(:mobile_gunner, context.stats, context.world_options)
    far_npc_id = "npc:1-1:rift_skirmisher:2"

    assert {:ok, _selection} =
             World.select_target(session.id, far_npc_id, context.world_options)

    assert {:ok, %{changed: true}} =
             World.engage_combat(session.id, context.world_options)

    assert {:ok, _movement} =
             World.move(session.id, %{x: 1_128.0, y: 1_000.0}, context.world_options)

    assert {:ok, tick} = World.tick("1-1", context.world_options)
    player = Enum.find(tick.entities, &(&1.id == :mobile_gunner))
    untouched = Enum.find(tick.entities, &(&1.id == far_npc_id))

    assert player.position == %{x: 1_032.0, y: 1_000.0}
    assert player.destination == %{x: 1_128.0, y: 1_000.0}
    assert player.target_id == far_npc_id
    assert player.engaged_target_id == far_npc_id
    assert untouched.shields == untouched.max_shields
    assert untouched.hull == untouched.max_hull

    assert {:ok, resumed_tick} = World.tick("1-1", context.world_options)
    resumed = Enum.find(resumed_tick.entities, &(&1.id == far_npc_id))
    assert resumed.shields < resumed.max_shields
    assert resumed.hull < resumed.max_hull
  end

  test "Ctrl and slot-one semantics share one laser toggle while preserving selection",
       context do
    assert {:ok, session} = World.connect(:toggle_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:rift_skirmisher:1"

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

    npc_id = "npc:1-1:rift_skirmisher:1"

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

  test "destroying one NPC permits a fresh toggle engagement with the next NPC", context do
    lethal_stats = %{context.stats | damage: 1_200}
    assert {:ok, session} = World.connect(:sequential_hunter, lethal_stats, context.world_options)
    first_npc_id = "npc:1-1:rift_skirmisher:1"
    second_npc_id = "npc:1-1:rift_skirmisher:2"

    assert {:ok, _selection} =
             World.select_target(session.id, first_npc_id, context.world_options)

    assert {:ok, %{active: true}} = World.toggle_laser_fire(session.id, context.world_options)
    assert {:ok, destroyed_tick} = World.tick("1-1", context.world_options)
    destroyed_player = Enum.find(destroyed_tick.entities, &(&1.id == :sequential_hunter))
    assert destroyed_player.target_id == nil
    assert destroyed_player.engaged_target_id == nil
    refute Enum.any?(destroyed_tick.entities, &(&1.id == first_npc_id))

    assert {:ok, _selection} =
             World.select_target(session.id, second_npc_id, context.world_options)

    assert {:ok, %{active: true, target_id: ^second_npc_id}} =
             World.toggle_laser_fire(session.id, context.world_options)

    assert {:ok, next_engagement} = World.snapshot("1-1", context.world_options)
    next_player = Enum.find(next_engagement.entities, &(&1.id == :sequential_hunter))
    assert next_player.target_id == second_npc_id
    assert next_player.engaged_target_id == second_npc_id
  end

  test "repeated engagement, empty actions, invalid actions, and cancellation are safe",
       context do
    assert {:ok, session} = World.connect(:action_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:rift_skirmisher:1"

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
    npc_id = "npc:1-1:rift_skirmisher:1"

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
    npc_id = "npc:1-1:rift_skirmisher:1"

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

    assert_receive {"1-1", :npc_spawned, %{id: ^npc_id, hull: 800, shields: 400, state: :idle}}

    assert {:ok, respawned_snapshot} = World.snapshot("1-1", context.world_options)
    respawned = Enum.find(respawned_snapshot.entities, &(&1.id == npc_id))
    assert respawned.position == %{x: 1_480.0, y: 1_000.0}
    assert respawned.hull == respawned.max_hull
    assert respawned.shields == respawned.max_shields
  end

  test "serializes concurrent and repeated attack attempts", context do
    assert {:ok, session} = World.connect(:rapid_pilot, context.stats, context.world_options)
    npc_id = "npc:1-1:rift_skirmisher:1"
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
               "npc:1-1:rift_skirmisher:1",
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
               "npc:1-1:rift_skirmisher:1",
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
end
