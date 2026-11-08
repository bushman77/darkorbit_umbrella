defmodule Core.World.GreenStarbaseImpactIntegrationTest do
  use ExUnit.Case

  alias Core.Ships.Stats
  alias Core.Universe.{FreeFlightRegion, GreenStarbase, Navigation}
  alias Core.World
  alias Core.World.{Position, Supervisor}

  @registry __MODULE__.Registry
  @sessions __MODULE__.Sessions
  @solar __MODULE__.SolarNavigation
  @supervisor __MODULE__.Supervisor
  @free_maps Module.concat(@sessions, FreeFlightMaps)
  @pilot 4_112
  @scale 0.06

  setup do
    receiver = self()
    event_sink = fn map, event, payload -> send(receiver, {map, event, payload}) end
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
    map_id = FreeFlightRegion.map_id(@pilot)
    opts = [registry: @registry, sessions: @sessions,
      solar_navigation_server: @solar, map_id: map_id]
    %{map_id: map_id, stats: stats, opts: opts}
  end

  defp at(x, y, z) do
    site = GreenStarbase.local_site()
    %Position{
      x: site.x + x / @scale,
      y: site.y + z / @scale,
      z: site.z + y / @scale
    }
  end

  defp near_starbase! do
    # Force the pilot's authoritative SOL waypoint in this isolated
    # simulation. The real Navigation.snapshot computes the nearby flag.
    assert {:ok, original} = Navigation.snapshot(@solar, @pilot)
    assert original.location_id == "earth"
    point = GreenStarbase.position_km()
    :sys.replace_state(@solar, fn state ->
      current = Map.fetch!(state.voyages, @pilot)
      updated = %{current |
        status: :idle, location_id: nil, origin_id: nil,
        arrival_origin_id: nil, destination_id: nil,
        position_km: point, origin_position_km: point,
        destination_position_km: nil}
      %{state | voyages: Map.put(state.voyages, @pilot, updated)}
    end)
    assert {:ok, %{green_starbase_nearby: true}} =
      Navigation.snapshot(@solar, @pilot)
  end

  defp connect!(ctx, position) do
    entry = %{position: position,
      attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}}
    assert {:ok, session} = World.connect(@pilot, ctx.stats,
      Keyword.put(ctx.opts, :entry, entry))
    session
  end

  defp tick!(ctx, count) do
    Enum.reduce(1..count, nil, fn _i, _last ->
      assert {:ok, state} = World.tick(ctx.map_id, ctx.opts)
      state
    end)
  end

  defp pilot(state), do: Enum.find(state.entities, &(&1.id == @pilot))

  test "server enables Green Starbase only near the actual SOL waypoint", ctx do
    session = connect!(ctx, at(0, 0, -60))
    assert {:ok, far} = World.snapshot(ctx.map_id, ctx.opts)
    assert far.station_warnings == []

    # A ship at the same LOCAL XY in unrelated deep space sees no starbase.
    assert {:ok, _} = World.move(session.id,
      Map.from_struct(at(28, 0, 5)), ctx.opts)
    far_movement = tick!(ctx, 32)
    assert far_movement.station_warnings == []
    assert pilot(far_movement).hull == ctx.stats.hit_points
    refute_receive {_, :station_collision, _}

    near_starbase!()
    # Presence is intentionally cached for 1 second; allow the public
    # Navigation gate to refresh before inspecting its world snapshot.
    state = tick!(ctx, 11)
    assert state.station_warnings != []
    assert state.station_warnings |> Enum.any?(&(&1.station_id == GreenStarbase.id()))
  end

  test "a true open central approach remains clear and rear wall stops the ship", ctx do
    near_starbase!()
    session = connect!(ctx, at(0, 0, -45))
    assert %{station_warnings: []} = elem(World.snapshot(ctx.map_id, ctx.opts), 1)
    assert %{station_warnings: _} = tick!(ctx, 1)

    assert {:ok, _} = World.move(session.id,
      Map.from_struct(at(0, 0, 0)), ctx.opts)
    inside = tick!(ctx, 25)
    assert pilot(inside).status == :alive
    assert pilot(inside).hull == ctx.stats.hit_points
    refute_receive {_, :station_collision, _}

    assert {:ok, _} = World.move(session.id,
      Map.from_struct(at(0, 0, 45)), ctx.opts)
    impacted = tick!(ctx, 24)
    ship = pilot(impacted)
    assert ship.status == :alive
    assert ship.hull < ctx.stats.hit_points
    assert ship.destination == nil
    assert_in_delta ship.position_3d.y,
      GreenStarbase.local_site().y + 23.0 / @scale, 2.0

    assert_receive {_, :station_collision,
      %{entity_id: @pilot, station_id: "sol:starbase:green",
        hull_part: :hangar_rear_wall, entity: %{status: :alive}}}

    # No subsequent idle impact spam.
    hull = ship.hull
    assert pilot(tick!(ctx, 2)).hull == hull
  end

  test "a swept side support impact stops autopilot outside the wall", ctx do
    near_starbase!()
    session = connect!(ctx, at(28, 0, -30))
    tick!(ctx, 1)
    assert {:ok, _} = World.move(session.id,
      Map.from_struct(at(28, 0, 10)), ctx.opts)
    state = tick!(ctx, 26)
    ship = pilot(state)
    assert ship.destination == nil
    assert ship.hull < ctx.stats.hit_points
    assert_receive {_, :station_collision,
      %{station_id: "sol:starbase:green", entity_id: @pilot,
        hull_part: part}}
    assert part in [:right_support, :right_brace, :left_support, :left_brace]
  end
end
