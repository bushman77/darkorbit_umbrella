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

    for _tick <- 1..5 do
      assert {:ok, _snapshot} = World.tick("1-1", context.world_options)
    end

    assert {:ok, snapshot} = World.snapshot("1-1", context.world_options)
    player = Enum.find(snapshot.entities, &(&1.id == :fragile_pilot))
    assert player.status == :destroyed
    assert player.hull == 0

    assert Enum.all?(
             Enum.filter(snapshot.entities, &(&1.kind == :npc)),
             &(&1.target_id != :fragile_pilot)
           )

    assert {:error, :attacker_destroyed} = World.attack(session.id, context.world_options)

    assert {:error, :attacker_destroyed} =
             World.move(session.id, %{x: 1_100, y: 1_000}, context.world_options)
  end
end
