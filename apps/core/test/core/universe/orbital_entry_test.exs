defmodule Core.Universe.OrbitalEntryTest do
  use ExUnit.Case, async: true

  alias Core.Universe.OrbitalEntry
  alias Core.Universe.PlanetaryView
  alias Core.Universe.Sol
  alias Core.World.FlightDynamics

  test "every registered planetary destination has exactly one true-scale orbital region" do
    maps = OrbitalEntry.planet_maps()
    assert length(maps) == length(Sol.planets())
    assert length(maps) == 9
    assert Enum.uniq(Enum.map(maps, & &1.id)) == Enum.map(maps, & &1.id)

    for id <- ~w(mercury venus earth mars jupiter saturn uranus neptune pluto) do
      region_id = "sol:" <> id
      map = Enum.find(maps, &(&1.id == region_id))
      assert map
      assert map.width == 400_000
      assert map.height == 400_000
      assert map.planet.body_id == id
      assert map.planet.center == OrbitalEntry.center(id)
      {:ok, radius} = PlanetaryView.radius_km(id)
      assert map.planet.radius_km == radius
      assert_in_delta map.planet.exclusion_radius, radius * 1.08, 1.0e-8
      assert map.spawn.x > map.planet.center.x + map.planet.exclusion_radius
      assert map.spawn.x < map.width
      assert map.altitude_min < 0
      assert map.altitude_max > 0
    end
    assert OrbitalEntry.map_id("earth") == "sol:earth"
    assert OrbitalEntry.map_id("venus") == "sol:venus"
    assert OrbitalEntry.map_id("sun") == nil
    assert OrbitalEntry.map_id("bogus") == nil
  end

  test "a fresh Earth pilot begins outside planetary caution and fatal zones" do
    assert {:ok, entry} = OrbitalEntry.entry(nil, "earth", 77, 0)
    assert entry.map_id == "sol:earth"
    assert entry.body_id == "earth"

    earth = Enum.find(OrbitalEntry.planet_maps(), &(&1.id == "sol:earth"))
    assert earth
    assert earth.planet.radius_km == 6_371.0
    assert Core.World.PlanetaryProximity.warning(entry.position, earth) == nil
    assert :clear ==
      Core.World.PlanetaryCollision.first_contact(
        entry.position, entry.position,
        earth.planet.center, earth.planet.exclusion_radius
      )
    assert entry.position.x >= 0 and entry.position.x <= earth.width
    assert entry.position.y >= 0 and entry.position.y <= earth.height
  end

  test "arrival from Earth to Venus is outside the planet and faces its centre" do
    assert {:ok, entry} = OrbitalEntry.entry("earth", "venus", 47, 3)
    assert entry.map_id == "sol:venus"
    assert entry.body_id == "venus"
    assert entry.source_id == "earth"

    center = entry.planet_center
    radius = PlanetaryView.radius_km("venus") |> elem(1)
    dx = entry.position.x - center.x
    dy = entry.position.y - center.y
    distance = :math.sqrt(dx * dx + dy * dy)

    assert_in_delta distance, radius * 1.861, 0.0001
    assert entry.position.x > 0.0
    assert entry.position.x < 400_000
    assert entry.position.y > 0.0
    assert entry.position.y < 400_000

    direction = FlightDynamics.forward(entry.attitude)
    inward = %{x: -dx / distance, y: -dy / distance}
    assert_in_delta direction.x, inward.x, 1.0e-9
    assert_in_delta direction.y, inward.y, 1.0e-9
    assert_in_delta direction.z, 0.0, 1.0e-9
  end

  test "two distinct approach origins produce materially different entry sides" do
    assert {:ok, from_earth} = OrbitalEntry.entry("earth", "venus", 1, 2)
    assert {:ok, from_mars} = OrbitalEntry.entry("mars", "venus", 1, 2)
    refute from_earth.position == from_mars.position

    # Local outward direction tracks the SOL origin minus the destination.
    {:ok, venus_sol} = Sol.game_position_km("venus")
    for {origin, entry} <- [{"earth", from_earth}, {"mars", from_mars}] do
      {:ok, origin_sol} = Sol.game_position_km(origin)
      expected_x = origin_sol.x - venus_sol.x
      expected_y = origin_sol.y - venus_sol.y
      expected_length = :math.sqrt(expected_x * expected_x + expected_y * expected_y)
      actual = entry.entry_direction
      cosine = actual.x * expected_x / expected_length +
        actual.y * expected_y / expected_length
      assert cosine > 0.99
    end
  end

  test "arrival is deterministic per voyage, with bounded staggering by player" do
    assert {:ok, first} = OrbitalEntry.entry("earth", "jupiter", 42, 1)
    assert {:ok, ^first} = OrbitalEntry.entry("earth", "jupiter", 42, 1)
    assert {:ok, second} = OrbitalEntry.entry("earth", "jupiter", 43, 1)
    refute first.position == second.position

    assert {:ok, return_earth} = OrbitalEntry.entry("venus", "earth", 42, 2)
    assert return_earth.map_id == "sol:earth"
    assert return_earth.position.x >= 0
    assert return_earth.position.x <= 400_000
    assert return_earth.position.y >= 0
    assert return_earth.position.y <= 400_000

    assert {:error, :invalid_planet} = OrbitalEntry.entry("earth", "sun", 42)
    assert {:error, :invalid_planet} = OrbitalEntry.entry("earth", "unknown", 42)
  end
end

