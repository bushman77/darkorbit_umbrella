defmodule Core.World.StationImpactIntegrationTest do
  use ExUnit.Case

  alias Core.Ships.Stats
  alias Core.Universe.OrbitalEntry
  alias Core.World
  alias Core.World.Position
  alias Core.World.Supervisor, as: WorldSupervisor

  @registry __MODULE__.Registry
  @sessions __MODULE__.Sessions
  @solar __MODULE__.SolarNavigation
  @supervisor __MODULE__.Supervisor

  setup do
    receiver = self()
    sink = fn map_id, event, payload -> send(receiver, {map_id, event, payload}) end
    earth = Enum.find(OrbitalEntry.planet_maps(), &(&1.id == "sol:earth"))
    base = OrbitalEntry.space_base("earth")
    start_supervised!(
      {WorldSupervisor,
       name: @supervisor, registry: @registry, sessions: @sessions,
       solar_navigation_server: @solar, maps: [earth], tick_ms: 100,
       auto_tick: false, initial_npcs?: false, auto_respawn?: false,
       event_sink: sink}
    )
    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    opts = [registry: @registry, sessions: @sessions,
            solar_navigation_server: @solar, map_id: "sol:earth"]
    %{base: base, stats: stats, opts: opts}
  end

  defp entry(base, offset) do
    pos = base.position_3d
    %{position: %Position{x: pos.x + offset, y: pos.y, z: pos.z},
      attitude: %{yaw: -:math.pi() / 2, pitch: 0.0, roll: 0.0}}
  end

  test "server tick stops autopilot at real station hull, not planet", ctx do
    opts = Keyword.put(ctx.opts, :entry, entry(ctx.base, 604.0))
    assert {:ok, session} = World.connect(:station_pilot, ctx.stats, opts)
    assert {:ok, _} = World.move(session.id,
      %{x: ctx.base.position_3d.x - 1_000.0,
        y: ctx.base.position_3d.y, z: ctx.base.position_3d.z}, ctx.opts)

    assert {:ok, state} = World.tick("sol:earth", ctx.opts)
    ship = Enum.find(state.entities, &(&1.id == :station_pilot))
    assert ship.status == :alive
    assert ship.hull < ctx.stats.hit_points
    assert ship.destination == nil
    assert_in_delta ship.position_3d.x,
      ctx.base.position_3d.x + ctx.base.collision_radius_km + 0.25, 0.01

    assert_receive {"sol:earth", :station_collision,
      %{entity_id: :station_pilot, station_id: "sol:base:earth",
        entity: %{status: :alive}}}
    refute_receive {"sol:earth", :entity_destroyed,
      %{reason: :planetary_collision}}

    # The stopped ship does not take more impact damage every idle tick.
    assert {:ok, next} = World.tick("sol:earth", ctx.opts)
    unchanged = Enum.find(next.entities, &(&1.id == :station_pilot))
    assert unchanged.hull == ship.hull
  end

  test "proximity is visible in snapshots and reports distinct transitions", ctx do
    opts = Keyword.put(ctx.opts, :entry, entry(ctx.base, 2_650))
    assert {:ok, session} = World.connect(:station_warn, ctx.stats, opts)
    assert {:ok, initial} = World.snapshot("sol:earth", ctx.opts)
    assert initial.station_warnings == []

    assert {:ok, _} = World.move(session.id,
      %{x: ctx.base.position_3d.x + 1_000.0,
        y: ctx.base.position_3d.y, z: ctx.base.position_3d.z}, ctx.opts)
    for _ <- 1..6, do: assert({:ok, _} = World.tick("sol:earth", ctx.opts))
    assert {:ok, near} = World.snapshot("sol:earth", ctx.opts)
    assert [%{entity_id: :station_warn, station_id: "sol:base:earth",
      level: :caution}] = near.station_warnings
    assert_receive {"sol:earth", :station_proximity_changed,
      %{entity_id: :station_warn, level: :caution}}
    refute_receive {"sol:earth", :planetary_proximity_changed,
      %{entity_id: :station_warn}}
  end
end
