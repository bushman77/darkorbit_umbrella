defmodule Core.NPC.CruiseRouteTest do
  use ExUnit.Case, async: true

  alias Core.NPC.CruiseRoute
  alias Core.Universe.Sol
  alias Core.World.MapDefinition
  alias Core.World.PlanetaryCollision
  alias Core.World.Position

  test "uses the real Earth-to-Venus SOL bearing, not an arbitrary square patrol" do
    position = %Position{x: 10_000.0, y: 6_000.0, z: 0.0}
    assert {:ok, route} =
      CruiseRoute.project("earth", "venus", position, MapDefinition.starting_map())

    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, venus} = Sol.game_position_km("venus")
    dx = venus.x - earth.x
    dy = venus.y - earth.y
    length = :math.sqrt(dx * dx + dy * dy)

    assert_in_delta route.heading.x, dx / length, 1.0e-9
    assert_in_delta route.heading.y, dy / length, 1.0e-9
    refute route.deflected?
    assert_in_delta route.destination.x - position.x,
      route.heading.x * CruiseRoute.lane_length(), 1.0e-7
    assert_in_delta route.destination.y - position.y,
      route.heading.y * CruiseRoute.lane_length(), 1.0e-7
  end

  test "avoids the real planet collision sphere while maintaining an outbound lane" do
    planet = %{
      body_id: "earth",
      center: %{x: 10_000.0, y: 10_000.0, z: 0.0},
      exclusion_radius: 7_000.0
    }
    map = %{MapDefinition.starting_map() | planet: planet}
    spawn = %Position{x: 18_000.0, y: 10_000.0, z: 0.0}

    # Intercept near Earth's eastern edge: a straight westbound Scow
    # trajectory would cut through the physical exclusion sphere.
    {:ok, from} = Sol.game_position_km("venus")
    {:ok, to} = Sol.game_position_km("earth")
    heading = %{x: to.x - from.x, y: to.y - from.y}
    # Construct a planet safely ahead of the ship's actual SOL bearing.
    magnitude = :math.sqrt(heading.x * heading.x + heading.y * heading.y)
    projected_center = %{x: spawn.x + heading.x / magnitude * 5_000.0,
                         y: spawn.y + heading.y / magnitude * 5_000.0,
                         z: spawn.z}
    map = %{map | planet: %{planet | center: projected_center,
                                    exclusion_radius: 1_500.0}}
    assert {:ok, route} = CruiseRoute.project("venus", "earth", spawn, map)
    assert route.deflected?
    assert :clear =
      PlanetaryCollision.first_contact(spawn, route.destination,
        projected_center, 1_500.0 + 350.0)
  end

  test "rejects forged or identical destinations before creating a map route" do
    pos = %Position{x: 10_000.0, y: 10_000.0}
    map = MapDefinition.starting_map()
    assert {:error, :invalid_cruise_route} =
      CruiseRoute.project("earth", "earth", pos, map)
    assert {:error, :invalid_cruise_route} =
      CruiseRoute.project("earth", "fake-system", pos, map)
  end
end
