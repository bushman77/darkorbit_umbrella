defmodule Core.World.AllPlanetRegionsIntegrationTest do
  use ExUnit.Case

  alias Core.Ships.Stats
  alias Core.Universe.OrbitalEntry
  alias Core.Universe.Sol
  alias Core.World
  alias Core.World.MapDefinition
  alias Core.World.PlanetaryCollision
  alias Core.World.PlanetaryProximity
  alias Core.World.Position
  alias Core.World.Supervisor, as: WorldSupervisor

  @registry __MODULE__.Registry
  @sessions __MODULE__.Sessions
  @solar __MODULE__.SolarNavigation
  @supervisor __MODULE__.Supervisor

  setup do
    owner = self()
    sink = fn map_id, event, payload -> send(owner, {map_id, event, payload}) end

    start_supervised!(
      {WorldSupervisor,
       name: @supervisor,
       registry: @registry,
       sessions: @sessions,
       solar_navigation_server: @solar,
       maps: OrbitalEntry.planet_maps(),
       tick_ms: 100,
       auto_tick: false,
       initial_npcs?: false,
       auto_respawn?: false,
       event_sink: sink}
    )

    {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})
    %{stats: stats,
      opts: [registry: @registry, sessions: @sessions,
             solar_navigation_server: @solar]}
  end

  test "every registered planet starts a map, warns, and kills on collision", ctx do
    planets = Sol.planets()
    assert length(planets) == 9

    for {planet, index} <- Enum.with_index(planets, 1) do
      region_id = OrbitalEntry.map_id(planet.id)
      map = Enum.find(OrbitalEntry.planet_maps(), &(&1.id == region_id))
      assert map
      assert {:ok, snapshot} = World.snapshot(region_id, ctx.opts)
      assert snapshot.map_id == region_id
      assert snapshot.planet_id == planet.id

      boundary = map.planet.exclusion_radius
      center = map.planet.center
      player_id = index + 2_000
      spawn = %{
        position: %Position{
          x: center.x + boundary + 10.0,
          y: center.y,
          z: center.z
        },
        attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
      }
      opts = ctx.opts |> Keyword.put(:map_id, region_id) |> Keyword.put(:entry, spawn)

      assert {:ok, session} = World.connect(player_id, ctx.stats, opts)
      assert {:ok, joined} = World.snapshot(region_id, ctx.opts)
      assert [%{entity_id: ^player_id, level: :critical,
                planet_id: planet_id}] = joined.planetary_warnings
      assert planet_id == planet.id

      assert {:ok, _} = World.move(session.id, %{
        x: center.x + boundary - 100.0, y: center.y, z: center.z
      }, ctx.opts)
      assert {:ok, after_tick} = World.tick(region_id, ctx.opts)
      ship = Enum.find(after_tick.entities, &(&1.id == player_id))
      assert ship.status == :destroyed
      assert ship.hull == 0
      assert ship.shields == 0
      assert ship.destination == nil
      assert_in_delta ship.position_3d.x, center.x + boundary, 1.0e-7

      assert_receive {^region_id, :entity_destroyed,
        %{entity: %{id: ^player_id, status: :destroyed},
          reason: :planetary_collision, planet_id: ^planet_id, attacker_id: nil}}

      assert {:ok, _} = World.tick(region_id, ctx.opts)
      refute_receive {^region_id, :entity_destroyed, %{entity: %{id: ^player_id}}}, 0
      assert {:error, :attacker_destroyed} =
        World.move(session.id, %{x: 100, y: 100}, ctx.opts)
    end
  end

  test "unlisted future world bodies use the same generic collision and warnings", _ctx do
    definition = %MapDefinition{
      id: "future:world-a",
      name: "Future planet orbital region",
      width: 200_000,
      height: 200_000,
      spawn: %Position{x: 120_000.0, y: 100_000.0, z: 0.0},
      planet: %{
        body_id: "world-a",
        center: %{x: 100_000.0, y: 100_000.0, z: 0.0},
        radius_km: 12_000.0,
        exclusion_radius: 12_960.0
      }
    }

    outside = %Position{x: 100_000.0 + 20_000.0, y: 100_000.0, z: 0.0}
    dangerous = %Position{x: 100_000.0 + 14_000.0, y: 100_000.0, z: 0.0}
    collision = %Position{x: 100_000.0 + 12_000.0, y: 100_000.0, z: 0.0}

    assert PlanetaryProximity.warning(outside, definition) == nil
    assert %{level: :critical, planet_id: "world-a"} =
      PlanetaryProximity.warning(dangerous, definition)
    assert {:hit, _position} = PlanetaryCollision.first_contact(
      dangerous, collision, definition.planet.center,
      definition.planet.exclusion_radius
    )
  end
end
