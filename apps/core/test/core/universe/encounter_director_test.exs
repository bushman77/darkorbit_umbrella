defmodule Core.Universe.EncounterDirectorTest do
  use ExUnit.Case, async: true

  alias Core.Universe.{EncounterDirector, Territory, Traffic}

  defp patrol_crossing do
    traffic = Traffic.seed()
    patrol = Map.fetch!(traffic, "traffic:sol:sentinel-07")

    voyage = %{
      status: :traveling,
      position_km: patrol.position_km,
      travel_distance_km: patrol.distance_km,
      distance_travelled_km: patrol.distance_km * 0.4
    }

    {traffic, voyage}
  end

  test "a real Venus patrol only attracts attention with poor standing in its zone" do
    {traffic, voyage} = patrol_crossing()
    {:ok, jurisdiction} = Territory.classify(voyage.position_km)
    assert Enum.any?(jurisdiction.claims, &(&1.faction_id == "venus"))

    assert %{contact_id: "traffic:sol:sentinel-07", faction_id: "venus",
             classification: :patrol_attention, mode: :strategic_flyby} =
      EncounterDirector.evaluate(traffic, voyage, %{"venus" => -25})

    assert %{classification: :neutral_flyby} =
      EncounterDirector.evaluate(traffic, voyage, %{"venus" => -24})

    assert %{classification: :neutral_flyby} =
      EncounterDirector.evaluate(traffic, voyage, %{"mercury" => -100})

    assert %{classification: :neutral_flyby} =
      EncounterDirector.evaluate(traffic, voyage)
  end

  test "hostile disposition wins without inventing new vessels or leaking cargo" do
    {traffic, voyage} = patrol_crossing()
    hostile = Map.update!(traffic, "traffic:sol:sentinel-07",
      &%{&1 | disposition: :hostile})

    assert %{classification: :hostile_contact, disposition: :hostile} =
      result = EncounterDirector.evaluate(hostile, voyage, %{"venus" => 100})
    refute Map.has_key?(result, :cargo)
    refute Map.has_key?(result, :manifest)
    refute Map.has_key?(result, :tactical_entity_id)
    assert map_size(hostile) == map_size(traffic)
    assert traffic == Traffic.seed()
  end

  test "patrol outside its own jurisdiction stays observational" do
    patrol = %{kind: :patrol, faction_id: "venus", disposition: :neutral}
    other_zone = %{claims: [%{faction_id: "mercury"}]}

    assert :neutral_flyby ==
      EncounterDirector.classify(patrol, other_zone, %{"venus" => -100})

    assert :neutral_flyby ==
      EncounterDirector.classify(patrol, %{claims: []}, %{"venus" => -100})
  end

  test "missing or invalid standings are neutral and idle voyages create no encounter" do
    {traffic, voyage} = patrol_crossing()
    assert %{classification: :neutral_flyby} =
      EncounterDirector.evaluate(traffic, voyage, %{"venus" => "hostile"})

    assert %{classification: :neutral_flyby} =
      EncounterDirector.evaluate(traffic, voyage, nil)

    assert EncounterDirector.evaluate(traffic, %{voyage | status: :idle}) == nil
    assert EncounterDirector.evaluate(traffic, %{voyage | distance_travelled_km: 0.0}) == nil
    assert EncounterDirector.evaluate(%{}, voyage) == nil
  end
end
