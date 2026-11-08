defmodule Core.World.GreenStarbaseDockingIntegrationTest do
  use ExUnit.Case, async: false

  alias Core.Ships.Stats
  alias Core.Universe.{FreeFlightRegion, GreenStarbase, Navigation}
  alias Core.World
  alias Core.World.{Position, Supervisor}

  @registry __MODULE__.Registry
  @sessions __MODULE__.Sessions
  @solar __MODULE__.SolarNavigation
  @supervisor __MODULE__.Supervisor
  @free_maps Module.concat(@sessions, FreeFlightMaps)
  @pilot 4_123

  setup do
    owner = self()
    event_sink = fn map, event, payload -> send(owner, {map, event, payload}) end
    start_supervised!({Supervisor,
      name: @supervisor, registry: @registry, sessions: @sessions,
      solar_navigation_server: @solar, maps: [], tick_ms: 100,
      auto_tick: false, initial_npcs?: false, auto_respawn?: false,
      event_sink: event_sink})
    assert :ok = FreeFlightRegion.ensure_started(@pilot,
      registry: @registry, supervisor: @free_maps,
      solar_navigation_server: @solar, auto_tick: false, tick_ms: 100,
      event_sink: event_sink)
    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    %{stats: stats, opts: [
      registry: @registry, sessions: @sessions,
      solar_navigation_server: @solar, map_id: FreeFlightRegion.map_id(@pilot)
    ]}
  end

  defp at(x, y, z) do
    origin = GreenStarbase.local_site()
    %Position{x: origin.x + x / 0.06, y: origin.y + z / 0.06,
      z: origin.z + y / 0.06}
  end

  defp at_starbase! do
    assert {:ok, _} = Navigation.snapshot(@solar, @pilot)
    position = GreenStarbase.position_km()
    :sys.replace_state(@solar, fn state ->
      voyage = Map.fetch!(state.voyages, @pilot)
      updated = %{voyage |
        status: :idle, location_id: nil, origin_id: nil,
        arrival_origin_id: nil, destination_id: nil,
        position_km: position, origin_position_km: position,
        destination_position_km: nil}
      %{state | voyages: Map.put(state.voyages, @pilot, updated)}
    end)
    assert {:ok, %{green_starbase_nearby: true}} = Navigation.snapshot(@solar, @pilot)
  end

  defp connect!(ctx, position) do
    entry = %{position: position, attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}}
    assert {:ok, session} = World.connect(@pilot, ctx.stats,
      Keyword.put(ctx.opts, :entry, entry))
    session
  end

  test "docking hides the real ship from combat and launching restores its hull", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, -10))
    assert {:ok, %{docked: false}} = World.docking_status(session.id, ctx.opts)
    assert {:ok, %{docked: true, station_id: "sol:starbase:green"}} =
      World.dock(session.id, ctx.opts)
    assert {:ok, %{docked: true}} = World.docking_status(session.id, ctx.opts)
    assert {:ok, %{docked: true, combat: %{status: :alive}}} =
      World.ship_condition(session.id, ctx.opts)
    assert {:ok, state} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert Enum.member?(state.docked_pilots, @pilot)
    refute Enum.any?(state.entities, &(&1.id == @pilot))
    assert {:error, :entity_not_found} =
      World.flight_controls(session.id, %{throttle: 1.0}, ctx.opts)
    assert {:error, :not_docked} =
      World.dock(session.id, ctx.opts)

    assert {:ok, %{docked: false, entity: entity}} =
      World.launch(session.id, ctx.opts)
    assert entity.hull == ctx.stats.hit_points
    assert {:ok, after_launch} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert after_launch.docked_pilots == []
    assert Enum.any?(after_launch.entities, &(&1.id == @pilot))
    assert {:error, :not_docked} = World.launch(session.id, ctx.opts)
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "server rejects requests outside the bay and away from the SOL waypoint", ctx do
    session = connect!(ctx, at(0, 0, -10))
    assert {:error, :not_at_starbase} = World.dock(session.id, ctx.opts)
    at_starbase!()
    assert :ok = World.disconnect(session.id, ctx.opts)
    session = connect!(ctx, at(0, 0, -45))
    assert {:error, :outside_docking_bay} = World.dock(session.id, ctx.opts)
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "a persisted docked pilot can be reparked after a fresh map join", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, 0))
    assert :ok = World.restore_dock(session.id, ctx.opts)
    assert {:ok, %{docked: true}} = World.docking_status(session.id, ctx.opts)
    assert :ok = World.disconnect(session.id, ctx.opts)
  end
end
