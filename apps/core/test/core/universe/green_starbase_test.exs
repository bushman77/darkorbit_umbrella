defmodule Core.Universe.GreenStarbaseTest do
  use ExUnit.Case, async: true
  alias Core.Universe.{GreenStarbase, Sol}

  test "the independent green starbase is a valid fixed Earth–Mars SOL waypoint" do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    point = GreenStarbase.position_km()
    assert point.x == (earth.x + mars.x) / 2
    assert point.y == (earth.y + mars.y) / 2
    assert {:ok, ^point} = Sol.waypoint(point)
    refute Sol.destination?(GreenStarbase.id())
    assert [%{id: "sol:starbase:green", model: :green_pyramid_starbase_v1,
              status: :approach_only, position_km: ^point}] =
      GreenStarbase.catalog()
  end

  test "visible only when the pilot is stopped near the correct deep-space waypoint" do
    point = GreenStarbase.position_km()
    assert GreenStarbase.nearby?(%{status: :idle, location_id: nil, position_km: point})
    refute GreenStarbase.nearby?(%{status: :traveling, location_id: nil, position_km: point})
    refute GreenStarbase.nearby?(%{status: :idle, location_id: "earth", position_km: point})
    refute GreenStarbase.nearby?(%{status: :idle, location_id: nil,
      position_km: %{point | z: 40_000.0}})
  end
end
