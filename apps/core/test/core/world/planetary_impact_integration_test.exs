defmodule Core.World.PlanetaryImpactIntegrationTest do
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
    event_sink = fn map_id, event, payload ->
      send(receiver, {map_id, event, payload})
    end

    venus = Enum.find(OrbitalEntry.planet_maps(), &(&1.id == "sol:venus"))
    start_supervised!(
      {WorldSupervisor,
       name: @supervisor,
       registry: @registry,
       sessions: @sessions,
       solar_navigation_server: @solar,
       maps: [venus],
       tick_ms: 100,
       auto_tick: false,
       initial_npcs?: false,
       auto_respawn?: false,
       event_sink: event_sink}
    )

    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    opts = [registry: @registry, sessions: @sessions,
            solar_navigation_server: @solar, map_id: "sol:venus"]

    %{stats: stats, opts: opts, planet: venus.planet}
  end

  defp entry(planet, clearance) do
    %{position: %Position{
        x: planet.center.x + planet.exclusion_radius + clearance,
        y: planet.center.y,
        z: 0.0
      },
      attitude: %{yaw: -:math.pi() / 2, pitch: 0.0, roll: 0.0}}
  end

  test "manual approach kills once, publishes planet impact, and disables controls", ctx do
    opts = Keyword.put(ctx.opts, :entry, entry(ctx.planet, 4.0))
    assert {:ok, session} = World.connect(:manual_crash, ctx.stats, opts)
    assert {:ok, _} =
      World.flight_controls(session.id, %{mode: "newtonian", throttle: 1.0}, ctx.opts)

    assert {:ok, snapshot} = World.tick("sol:venus", ctx.opts)
    ship = Enum.find(snapshot.entities, &(&1.id == :manual_crash))
    assert ship.status == :destroyed
    assert ship.hull == 0
    assert ship.shields == 0
    assert ship.destination == nil
    assert ship.velocity == %{x: 0.0, y: 0.0, z: 0.0}
    assert_in_delta ship.position_3d.x,
      ctx.planet.center.x + ctx.planet.exclusion_radius, 1.0e-7

    assert_receive {"sol:venus", :entity_destroyed,
      %{entity: %{id: :manual_crash, status: :destroyed},
        reason: :planetary_collision, planet_id: "venus",
        attacker_id: nil, respawn_tick: nil}}

    assert {:error, :attacker_destroyed} =
      World.flight_controls(session.id, %{throttle: 1.0}, ctx.opts)
    assert {:error, :attacker_destroyed} =
      World.move(session.id, %{x: 220_000, y: 200_000}, ctx.opts)
    assert {:error, :attacker_destroyed} = World.attack(session.id, ctx.opts)

    for _ <- 1..4, do: assert({:ok, _} = World.tick("sol:venus", ctx.opts))
    refute_receive {"sol:venus", :entity_destroyed,
      %{entity: %{id: :manual_crash}}}
  end

  test "plotted autopilot also crashes before crossing the planet", ctx do
    opts = Keyword.put(ctx.opts, :entry, entry(ctx.planet, 3.0))
    assert {:ok, session} = World.connect(:autopilot_crash, ctx.stats, opts)
    assert {:ok, _} = World.move(session.id, %{
      x: ctx.planet.center.x + ctx.planet.exclusion_radius - 150.0,
      y: ctx.planet.center.y,
      z: 0.0
    }, ctx.opts)

    assert {:ok, snapshot} = World.tick("sol:venus", ctx.opts)
    ship = Enum.find(snapshot.entities, &(&1.id == :autopilot_crash))
    assert ship.status == :destroyed
    assert_in_delta ship.position_3d.x,
      ctx.planet.center.x + ctx.planet.exclusion_radius, 1.0e-7
    assert ship.destination == nil

    assert_receive {"sol:venus", :entity_destroyed,
      %{entity: %{id: :autopilot_crash}, reason: :planetary_collision}}
  end

  test "safe arrivals and flight away from Venus never cause damage", ctx do
    opts = Keyword.put(ctx.opts, :entry, entry(ctx.planet, 2_000.0))
    assert {:ok, session} = World.connect(:safe_pilot, ctx.stats, opts)
    assert {:ok, _} = World.flight_controls(session.id, %{
      mode: "newtonian", throttle: -1.0
    }, ctx.opts)
    # Nose faces inward, so reverse thrust moves the vessel farther out.
    for _ <- 1..10, do: assert({:ok, _} = World.tick("sol:venus", ctx.opts))
    assert {:ok, snapshot} = World.snapshot("sol:venus", ctx.opts)
    ship = Enum.find(snapshot.entities, &(&1.id == :safe_pilot))
    assert ship.status == :alive
    assert ship.hull == ctx.stats.hit_points
    assert ship.position_3d.x > ctx.planet.center.x + ctx.planet.exclusion_radius
    refute_receive {"sol:venus", :entity_destroyed,
      %{entity: %{id: :safe_pilot}}}
  end
end
