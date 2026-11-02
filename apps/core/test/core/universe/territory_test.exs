defmodule Core.Universe.TerritoryTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Sol
  alias Core.Universe.Territory

  defp zone(id, x, radius, y \\ 0.0, z \\ 0.0) do
    %{
      id: id,
      faction_id: id,
      center_km: %{x: x, y: y, z: z},
      radius_km: radius
    }
  end

  test "the SOL catalog contains nine independently claimed, planet-centred spheres" do
    definitions = Territory.zones()

    assert Enum.map(definitions, & &1.id) ==
             ~w(mercury venus earth mars jupiter saturn uranus neptune pluto)

    for definition <- definitions do
      assert definition.faction_id == definition.id
      assert definition.radius_km > 0
      assert {:ok, position} = Sol.game_position_km(definition.id)
      assert definition.center_km == position
      assert {:ok, result} = Territory.classify(position, [definition])
      assert result.status == :controlled
      assert hd(result.claims).influence == 1.0
    end

    assert {:ok, %{status: :unclaimed, claims: []}} =
             Territory.classify(%{x: 0, y: 0, z: 0}, [])
  end

  test "radii can be tuned by the server without changing coordinates or owners" do
    default_earth = Territory.zones() |> Enum.find(&(&1.id == "earth"))

    adjusted =
      Territory.zones(radii_km: %{"earth" => 700_000.0})
      |> Enum.find(&(&1.id == "earth"))

    assert adjusted.center_km == default_earth.center_km
    assert adjusted.faction_id == "earth"
    assert adjusted.radius_km == 700_000.0
    assert adjusted.radius_km != default_earth.radius_km

    assert_raise ArgumentError, fn -> Territory.zones(radius_fraction: -0.1) end
    assert_raise ArgumentError, fn ->
      Territory.zones(radii_km: %{"earth" => -1})
    end
  end

  test "one claim is controlled, two independent claims are contested, and no claims unclaimed" do
    earth = zone("earth", 0.0, 5.0)
    mars = zone("mars", 8.0, 5.0)

    assert {:ok, %{status: :controlled, claims: [claim]}} =
             Territory.classify({0.0, 0.0, 0.0}, [earth, mars])

    assert claim.faction_id == "earth"
    assert claim.normalized_distance == 0.0

    assert {:ok, %{status: :contested, claims: [first, second]}} =
             Territory.classify(%{x: 4.0, y: 0.0, z: 0.0}, [earth, mars])

    assert [first.faction_id, second.faction_id] == ["earth", "mars"]
    assert_in_delta first.influence, 0.2, 0.000_001
    assert_in_delta second.influence, 0.2, 0.000_001

    assert {:ok, %{status: :unclaimed, claims: []}} =
             Territory.classify({100.0, 0.0, 0.0}, [earth, mars])
  end

  test "ZOC membership uses full XYZ, includes the boundary and has no infinite vertical cylinder" do
    earth = zone("earth", 0, 5)

    assert {:ok, %{status: :controlled}} = Territory.classify({3, 0, 4}, [earth])
    assert {:ok, %{status: :unclaimed}} = Territory.classify({3, 0, 4.01}, [earth])
    assert {:ok, %{status: :unclaimed}} = Territory.classify({0, 0, 6}, [earth])

    assert {:error, :invalid_position} = Territory.classify({1, 2}, [earth])
    assert {:error, :invalid_position} = Territory.classify(%{x: "1", y: 2, z: 3}, [earth])
    assert {:error, :invalid_zone} = Territory.classify({0, 0, 0}, [%{earth | radius_km: 0}])
    assert {:error, :invalid_zone} = Territory.classify({0, 0, 0}, [earth, earth])
  end

  test "a straight interplanetary transit reports ordered entry and exit events" do
    spheres = [zone("earth", 0, 5), zone("mars", 8, 5)]

    assert {:ok, events} = Territory.crossings({-10, 0, 0}, {18, 0, 0}, spheres)
    assert Enum.map(events, &{&1.faction_id, &1.kind}) == [
             {"earth", :entered},
             {"mars", :entered},
             {"earth", :exited},
             {"mars", :exited}
           ]

    assert Enum.map(events, & &1.position_km.x) ==
             [-5.0, 3.0, 5.0, 13.0]

    fractions = Enum.map(events, & &1.fraction)
    assert fractions == Enum.sort(fractions)

    assert {:ok, %{status: :contested}} =
             Territory.classify({4, 0, 0}, spheres)
  end

  test "tangencies, zero length and shared segment endpoints do not double count crossings" do
    sphere = zone("earth", 0, 5)

    assert {:ok, []} = Territory.crossings({0, 5, 0}, {10, 5, 0}, [sphere])
    assert {:ok, []} = Territory.crossings({0, 0, 0}, {0, 0, 0}, [sphere])
    assert {:ok, []} = Territory.crossings({-5, 0, 0}, {0, 0, 0}, [sphere])
    assert {:ok, []} = Territory.crossings({0, 0, 0}, {5, 0, 0}, [sphere])

    assert {:error, :invalid_position} =
             Territory.crossings({0, 0}, {10, 0, 0}, [sphere])
  end

  test "existing SOL navigation coordinates can be evaluated without local-sector conversion" do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    definitions = Territory.zones()

    assert {:ok, earth_classification} = Territory.classify(earth, definitions)
    assert Enum.any?(earth_classification.claims, &(&1.faction_id == "earth"))

    assert {:ok, mars_classification} = Territory.classify(mars, definitions)
    assert Enum.any?(mars_classification.claims, &(&1.faction_id == "mars"))

    assert {:ok, crossings} = Territory.crossings(earth, mars, definitions)
    assert Enum.any?(crossings, &(&1.faction_id == "earth" and &1.kind == :exited))
    assert Enum.any?(crossings, &(&1.faction_id == "mars" and &1.kind == :entered))
  end
end
