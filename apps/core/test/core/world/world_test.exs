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
    assert [%{position: %{x: 1_000.0, y: 1_000.0}}] = initial.entities

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

    assert [%{position: %{x: x, y: y}, destination: nil}] = final.entities
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
    assert [%{position: %{x: 1_000.0, y: 1_000.0}, destination: nil}] = snapshot.entities
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
end
