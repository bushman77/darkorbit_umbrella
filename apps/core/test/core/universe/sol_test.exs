defmodule Core.Universe.SolTest do
  use ExUnit.Case, async: true
  alias Core.Universe.Sol

  test "Sol has one star, all eight planets and Pluto in AU order" do
    names = Sol.all() |> Enum.map(& &1.name)
    assert names == ~w(Sun Mercury Venus Earth Mars Jupiter Saturn Uranus Neptune Pluto)
    assert {:ok, %{kind: :dwarf_planet, au: 39.482}} = Sol.fetch("pluto")
    assert Sol.destination?("pluto")
    assert Sol.destination?("earth")
    refute Sol.destination?("sun")
    refute Sol.destination?("nowhere")
    assert :error == Sol.fetch(nil)
  end

  test "every navigable planetary body has one canonical positive physical radius" do
    planets = Sol.planets()
    assert length(planets) == 9
    assert Enum.uniq(Enum.map(planets, & &1.id)) == Enum.map(planets, & &1.id)

    for %{id: id, radius_km: expected} <- planets do
      assert is_float(expected)
      assert expected > 0
      assert {:ok, radius} = Sol.planet_radius_km(id)
      assert_in_delta radius, expected, 1.0e-9
      assert {:ok, ^radius} = Core.Universe.PlanetaryView.radius_km(id)
    end

    assert {:ok, 6_371.0} = Sol.planet_radius_km("earth")
    assert {:ok, 6_051.8} = Sol.planet_radius_km("venus")
    assert :error = Sol.planet_radius_km("sun")
    assert :error = Sol.planet_radius_km("unknown")
  end

  test "sublight cruise covers compressed game distances in several real minutes" do
    assert Sol.cruise_speed_km_s() < Sol.light_speed_km_s()
    assert Sol.cruise_speed_km_s() > 0
    mars = Sol.travel_duration_ms("earth", "mars")
    jupiter = Sol.travel_duration_ms("earth", "jupiter")
    neptune = Sol.travel_duration_ms("earth", "neptune")
    pluto = Sol.travel_duration_ms("earth", "pluto")
    assert mars in 180_000..360_000
    assert jupiter in 420_000..780_000
    assert neptune > jupiter
    assert pluto >= 1_200_000
    assert pluto > mars
    assert rem(mars, 1_000) == 0
  end

  test "gameplay SOL positions are finite and distinct from physical AU" do
    assert {:ok, earth} = Sol.game_position_km("earth")
    assert {:ok, mars} = Sol.game_position_km("mars")
    assert earth.z == 0.0
    assert Sol.game_position_km("bogus") == :error
    assert Sol.cruise_distance_km("earth", "mars") > 0
    middle = Sol.interpolate_game_position(earth, mars, 0.5)
    assert_in_delta middle.x, (earth.x + mars.x) / 2, 0.0001
    assert_in_delta middle.y, (earth.y + mars.y) / 2, 0.0001
    assert_in_delta Sol.cruise_distance_km("earth", "mars"),
      Sol.cruise_speed_km_s() * Sol.travel_duration_ms("earth", "mars") / 1000,
      Sol.cruise_speed_km_s()
  end
end
