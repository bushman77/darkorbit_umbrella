defmodule Core.World.PlanetaryProximityTest do
  use ExUnit.Case, async: true

  alias Core.Universe.OrbitalEntry
  alias Core.World.PlanetaryProximity
  alias Core.World.Position

  defp venus do
    OrbitalEntry.planet_maps() |> Enum.find(&(&1.id == "sol:venus"))
  end

  defp at_radius(planet, radial) do
    %Position{
      x: planet.center.x + radial,
      y: planet.center.y,
      z: planet.center.z
    }
  end

  test "normal approach enters neither warning band" do
    map = venus()
    {:ok, entry} = OrbitalEntry.entry("earth", "venus", 41, 1)
    assert PlanetaryProximity.warning(entry.position, map) == nil
    assert PlanetaryProximity.level(nil) == :clear
    assert PlanetaryProximity.warning(entry.position, Core.World.MapDefinition.starting_map()) == nil
  end

  test "warnings escalate by actual 3D distance to the server-owned lethal sphere" do
    map = venus()
    boundary = map.planet.exclusion_radius
    caution = PlanetaryProximity.warning(at_radius(map.planet, boundary * 1.50), map)
    assert caution.planet_id == "venus"
    assert caution.level == :caution
    assert_in_delta caution.clearance_km, boundary * 0.50, 1.0e-6
    assert_in_delta caution.distance_km, boundary * 1.50, 1.0e-6
    assert caution.lethal_radius_km == boundary

    critical = PlanetaryProximity.warning(at_radius(map.planet, boundary * 1.10), map)
    assert critical.level == :critical
    assert critical.clearance_km > 0
    assert critical.clearance_km < caution.clearance_km
    assert PlanetaryProximity.level(critical) == :critical

    # X/Y alone are insufficient: an elevated approach is not a threat.
    elevated = %Position{
      x: map.planet.center.x,
      y: map.planet.center.y,
      z: boundary * 1.70
    }
    assert PlanetaryProximity.warning(elevated, map) == nil
  end

  test "only changes to the zone trigger transitions, including retreat to clear" do
    map = venus()
    boundary = map.planet.exclusion_radius
    caution = PlanetaryProximity.warning(at_radius(map.planet, boundary * 1.4), map)
    still_caution = PlanetaryProximity.warning(at_radius(map.planet, boundary * 1.3), map)
    critical = PlanetaryProximity.warning(at_radius(map.planet, boundary * 1.1), map)

    assert %{level: :caution, previous_level: :clear, tick: 2,
             entity_id: 12, planet_id: "venus"} =
      PlanetaryProximity.transition(12, nil, caution, 2)
    assert PlanetaryProximity.transition(12, caution, still_caution, 3) == nil
    assert %{level: :critical, previous_level: :caution} =
      PlanetaryProximity.transition(12, caution, critical, 4)
    assert %{level: :caution, previous_level: :critical} =
      PlanetaryProximity.transition(12, critical, caution, 5)
    assert %{level: :clear, previous_level: :caution, clearance_km: nil} =
      PlanetaryProximity.transition(12, caution, nil, 6)
    assert PlanetaryProximity.transition(12, nil, nil, 7) == nil
  end
end
