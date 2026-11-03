defmodule Core.Universe.EncountersTest do
  use ExUnit.Case, async: true

  alias Core.Universe.{Encounters, Sol, Traffic}

  defp voyage(destination_id, progress) do
    {:ok, start_pos} = Sol.game_position_km("earth")
    {:ok, end_pos} = Sol.game_position_km(destination_id)
    length = Sol.cruise_distance_km("earth", destination_id)

    %{
      status: :traveling,
      origin_id: "earth",
      destination_id: destination_id,
      origin_position_km: start_pos,
      destination_position_km: end_pos,
      position_km: Sol.interpolate_game_position(start_pos, end_pos, progress),
      travel_distance_km: length,
      distance_travelled_km: length * progress
    }
  end

  test "the existing Earth-Venus courier is a real close-pass encounter" do
    # Courier began 22% into the route at its own independently advancing
    # 42k game-km/s. Player accelerates through that traffic at 65k km/s.
    traffic = Traffic.advance(Traffic.seed(), 109_000)
    cruise = voyage("venus", 109_000.0 * Sol.cruise_speed_km_s() /
      Sol.cruise_distance_km("earth", "venus"))

    assert encounter = Encounters.nearest(traffic, cruise)
    assert encounter.contact_id == "traffic:sol:vesper-02"
    assert encounter.call_sign == "Vesper-02"
    assert encounter.mode == :strategic_flyby
    assert encounter.disposition == :neutral
    assert encounter.distance_km < Encounters.encounter_radius_km()
    assert encounter.id == "flyby:traffic:sol:vesper-02:1"
    refute Map.has_key?(encounter, :cargo)
    refute Map.has_key?(encounter, :manifest)
    refute Map.has_key?(encounter, :tactical_entity_id)

    relative = encounter.relative_position_km
    assert_in_delta :math.sqrt(relative.x * relative.x +
      relative.y * relative.y + relative.z * relative.z),
      encounter.distance_km, 1.0e-5
  end

  test "close passes require an actual moving contact and mid-route position" do
    ships = Traffic.seed()
    assert Encounters.nearest(ships, voyage("venus", 0.0)) == nil
    assert Encounters.nearest(ships, voyage("venus", 0.02)) == nil
    assert Encounters.nearest(ships, voyage("venus", 0.99)) == nil
    assert Encounters.nearest(ships, %{voyage("venus", 0.5) | status: :idle}) == nil
    assert Encounters.nearest(%{}, voyage("venus", 0.5)) == nil

    # Even if the pilot's route passes a docked freighter, it isn't a live
    # mid-space flyby. Hailing docked craft remains possible via sensors.
    ship = hd(Map.values(ships))
    immobile = %{ship | state: :docked, position_km: voyage("venus", 0.5).position_km}
    assert Encounters.nearest(%{ship.id => immobile}, voyage("venus", 0.5)) == nil
  end
end
