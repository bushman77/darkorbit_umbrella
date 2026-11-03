defmodule Core.Universe.PlanetaryViewTest do
  use ExUnit.Case, async: true

  alias Core.Universe.PlanetaryView
  alias Core.Universe.Sol

  defp transit(destination, fraction) do
    %{status: :traveling, destination_id: destination,
      travel_distance_km: 10_000_000.0,
      distance_travelled_km: 10_000_000.0 * fraction}
  end

  test "Venus has its actual mean radius, independent of compressed SOL game-km" do
    assert {:ok, 6_051.8} = PlanetaryView.radius_km("venus")
    assert {:ok, 6_371.0} = PlanetaryView.radius_km("earth")
    assert :error = PlanetaryView.radius_km("made-up-planet")
    assert Sol.cruise_distance_km("earth", "venus") > 10_000_000
  end

  test "a planet starts small, grows smoothly on approach and appears huge at arrival" do
    views = for fraction <- [0.0, 0.25, 0.5, 0.75, 0.9, 1.0],
      do: PlanetaryView.describe(transit("venus", fraction))
    angles = Enum.map(views, & &1.angular_diameter_deg)
    assert angles == Enum.sort(angles)
    assert hd(angles) == 1.5
    assert List.last(angles) == 65.0

    Enum.each(views, fn view ->
      assert view.body_id == "venus"
      assert view.visual_only
      assert view.stage == :approach_preview
      assert view.visual_distance_km > view.radius_km

      actual_angle = 2 * :math.asin(view.radius_km / view.visual_distance_km) *
        180 / :math.pi()
      assert_in_delta actual_angle, view.angular_diameter_deg, 1.0e-9
    end)
  end

  test "an idle ship has a dominant but safe planetary orbital staging view" do
    venus = PlanetaryView.describe(%{status: :idle, location_id: "venus"})
    assert venus.body_id == "venus"
    assert venus.stage == :orbital_preview
    assert venus.angular_diameter_deg == 65.0
    assert_in_delta venus.radius_km, 6_051.8, 0.001
    assert venus.visual_distance_km > venus.radius_km * 1.8
    assert venus.visual_distance_km < venus.radius_km * 2.0

    assert PlanetaryView.describe(%{status: :idle, location_id: "sun"}) == nil
    assert PlanetaryView.describe(%{status: :traveling, destination_id: "sun",
      travel_distance_km: 1, distance_travelled_km: 0}) == nil
    assert PlanetaryView.describe(%{status: :invalid}) == nil
  end

  test "malformed progress is safely bounded within the expected presentation size" do
    beyond = PlanetaryView.describe(transit("earth", 2.0))
    before = PlanetaryView.describe(transit("earth", -1.0))
    assert beyond.angular_diameter_deg == 65.0
    assert before.angular_diameter_deg == 1.5
  end
end
