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
    assert {:error, :ship_docked} =
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

  test "parked pilot walks with server-owned bounds; launch rejects walking", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, -10))
    assert {:error, :not_docked} =
      World.station_walk(session.id, %{"forward" => 1, "strafe" => 0, "turn" => 0}, ctx.opts)
    assert {:ok, %{docked: true}} = World.dock(session.id, ctx.opts)
    assert {:error, :invalid_station_controls} =
      World.station_walk(session.id, %{"forward" => 55, "strafe" => 0, "turn" => 0}, ctx.opts)
    assert {:ok, _} =
      World.station_walk(session.id, %{"forward" => 1, "strafe" => 0, "turn" => 0}, ctx.opts)
    for _ <- 1..15, do: assert {:ok, _} = World.tick(ctx.opts[:map_id], ctx.opts)
    assert {:ok, snapshot} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert [%{player_id: @pilot, z: z}] = snapshot.station_avatars
    assert z < 43.0
    assert {:ok, %{station_position: %{z: ^z}}} =
      World.ship_condition(session.id, ctx.opts)
    assert {:ok, _} = World.station_look(session.id, %{"delta_yaw" => 0.15}, ctx.opts)
    assert {:ok, snapshot} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert [%{yaw: yaw}] = snapshot.station_avatars
    assert yaw > 0.1
    assert {:ok, _} = World.launch(session.id, ctx.opts)
    assert {:error, :not_docked} =
      World.station_walk(session.id, %{"forward" => 1, "strafe" => 0, "turn" => 0}, ctx.opts)
    assert {:ok, after_launch} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert after_launch.station_avatars == []
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "room transition is server-owned and included in the parked ship report", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, -10))
    assert {:ok, %{docked: true}} = World.dock(session.id, ctx.opts)
    assert {:ok, _} = World.station_walk(session.id,
      %{"forward" => 1, "strafe" => 0, "turn" => 0}, ctx.opts)

    # At 14 units/s and 100 ms per tick, the pilot travels 1.4 units per
    # tick. After 105 ticks, z is near -104: still inside the airlock.
    for _ <- 1..105, do: assert {:ok, _} = World.tick(ctx.opts[:map_id], ctx.opts)
    assert {:ok, %{station_position: %{room_id: "airlock", z: airlock_z}}} =
      World.ship_condition(session.id, ctx.opts)
    assert_in_delta airlock_z, -104.0, 0.1

    # Continue walking through the threshold; do not weaken server collision
    # or expect a concourse transition before physically reaching its door.
    for _ <- 1..7, do: assert {:ok, _} = World.tick(ctx.opts[:map_id], ctx.opts)
    assert {:ok, %{station_position: %{room_id: "concourse", z: z}}} =
      World.ship_condition(session.id, ctx.opts)
    assert z < -106
    assert {:ok, snap} = World.snapshot(ctx.opts[:map_id], ctx.opts)
    assert [%{room_id: "concourse", player_id: @pilot}] = snap.station_avatars
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "server rejects requests outside the bay and away from the SOL waypoint", ctx do
    session = connect!(ctx, at(0, 0, -45))
    assert {:error, :not_at_starbase} = World.dock(session.id, ctx.opts)
    at_starbase!()
    assert {:error, :outside_docking_bay} = World.dock(session.id, ctx.opts)
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "staying stopped inside the real hangar auto-docks after five seconds", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, -10))
    map_id = ctx.opts[:map_id]

    assert {:ok, %{docked: false}} = World.docking_status(session.id, ctx.opts)
    assert {:ok, first} = World.tick(map_id, ctx.opts)
    assert [%{entity_id: @pilot, started_tick: 1, duration_ms: 5_000}] =
      first.docking_holds
    assert_receive {^map_id, :station_docking_started,
      %{entity_id: @pilot, duration_ms: 5_000}}

    for _ <- 1..49 do
      assert {:ok, snapshot} = World.tick(map_id, ctx.opts)
      assert snapshot.docked_pilots == []
    end

    assert {:ok, complete} = World.tick(map_id, ctx.opts)
    assert complete.docked_pilots == [@pilot]
    assert complete.docking_holds == []
    assert_receive {^map_id, :station_docked, %{entity_id: @pilot}}
    assert {:ok, %{docked: true}} = World.docking_status(session.id, ctx.opts)
    assert {:error, :entity_not_found} =
      World.flight_controls(session.id, %{throttle: 1.0}, ctx.opts)
    assert :ok = World.disconnect(session.id, ctx.opts)
  end

  test "moving before five seconds cancels instead of auto-docking", ctx do
    at_starbase!()
    session = connect!(ctx, at(0, 0, -10))
    map_id = ctx.opts[:map_id]
    assert {:ok, %{docking_holds: [_]}} = World.tick(map_id, ctx.opts)
    assert_receive {^map_id, :station_docking_started, %{entity_id: @pilot}}

    # The real throttle channel changes the map-owned ship. A stationary
    # client countdown must not bypass this authoritative movement state.
    assert {:ok, _} = World.flight_controls(
      session.id, %{throttle: 0.75}, ctx.opts)
    assert {:ok, cancelled} = World.tick(map_id, ctx.opts)
    assert cancelled.docking_holds == []
    assert_receive {^map_id, :station_docking_cancelled, %{entity_id: @pilot}}
    assert {:ok, %{docked: false}} = World.docking_status(session.id, ctx.opts)
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
