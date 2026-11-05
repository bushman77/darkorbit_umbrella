defmodule Core.Universe.FreeFlightRegionTest do
  use ExUnit.Case, async: true
  alias Core.Universe.{FreeFlightRegion, Sol}

  test "private regions are deterministic and have no physical planet" do
    a = FreeFlightRegion.definition(10)
    b = FreeFlightRegion.definition(11)
    assert a.id == "sol:free_10"
    assert b.id == "sol:free_11"
    assert a.id != b.id
    assert a.planet == nil
    assert a.spawn.x > 0 and a.spawn.x < a.width
    assert a.spawn.y > 0 and a.spawn.y < a.height
  end

  test "entry derives the heading from SOL's actual route" do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    voyage = %{status: :traveling, free_flight: true,
      origin_position_km: earth, destination_position_km: mars}
    assert {:ok, entry} = FreeFlightRegion.entry(19, voyage)
    assert entry.map_id == "sol:free_19"
    assert entry.position.z == 0.0
    assert is_number(entry.attitude.yaw)
    assert {:ok, cruise_cockpit} =
      FreeFlightRegion.entry(19, %{voyage | free_flight: false})
    assert cruise_cockpit.map_id == entry.map_id
    assert {:ok, idle_space} =
      FreeFlightRegion.entry(19, %{status: :idle, location_id: nil,
        position_km: earth})
    assert idle_space.map_id == entry.map_id
    assert {:error, :free_flight_unavailable} =
      FreeFlightRegion.entry(19, %{status: :idle, location_id: "earth"})
  end
end
