defmodule Core.Universe.TradeLanesTest do
  use ExUnit.Case, async: true

  alias Core.Universe.{Encounters, Sol, TradeLanes, Traffic}

  test "traffic pressure increases smoothly toward any planet, independent of destination" do
    {:ok, earth} = Sol.game_position_km("earth")

    # Offset above the SOL ecliptic to avoid unrelated surface corridors.
    near = %{earth | z: 900_000.0}
    middle = %{earth | z: 3_000_000.0}
    outside = %{earth | z: 10_000_000.0}

    assert TradeLanes.pressure(near) > TradeLanes.pressure(middle)
    assert TradeLanes.pressure(middle) > TradeLanes.pressure(outside)
    assert TradeLanes.pressure(outside) == 0.0
    assert TradeLanes.band(near) in [:moderate, :busy]
    assert TradeLanes.band(outside) == :quiet
  end

  test "inbound vector, not destination type, controls approach encounter bonus" do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    approach = Sol.interpolate_game_position(earth, mars, 0.95)

    toward_mars = %{
      position_km: approach,
      origin_position_km: earth,
      destination_position_km: mars,
      destination_id: nil
    }
    away_from_mars = %{
      position_km: approach,
      origin_position_km: mars,
      destination_position_km: earth,
      destination_id: nil
    }

    assert TradeLanes.inbound_pressure(toward_mars) >
      TradeLanes.inbound_pressure(away_from_mars)
    assert Encounters.encounter_radius_km(toward_mars) >
      Encounters.encounter_radius_km(away_from_mars)
  end

  test "corridors contribute pressure even far from planetary endpoints" do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    middle = Sol.interpolate_game_position(earth, mars, 0.5)
    away = %{middle | z: 5_000_000.0}

    assert TradeLanes.pressure(middle) > TradeLanes.pressure(away)
    assert TradeLanes.pressure(middle) > 0.0
    assert {"earth", "mars"} in TradeLanes.departures()
    assert {"mars", "earth"} in TradeLanes.departures()
  end

  test "scheduled ships have real origins, not pilot-selected destinations" do
    assert {:ok, ships} =
      Traffic.launch_scheduled_trader(Traffic.seed(), "jupiter", "mars", 901)
    ship = Map.fetch!(ships, "traffic:sol:cruise-901")

    assert ship.kind == :independent_trader
    assert ship.origin_id == "jupiter"
    assert ship.destination_id == "mars"
    assert ship.position_km == elem(Sol.game_position_km("jupiter"), 1)
    assert ship.ship_class == "scow"

    assert {:ok, moved} = {:ok, Traffic.advance(ships, 30_000)}
    assert moved[ship.id].position_km != ship.position_km
    assert moved[ship.id].origin_id == "jupiter"
    assert moved[ship.id].destination_id == "mars"
    assert {:error, :invalid_route} =
      Traffic.launch_scheduled_trader(ships, "mars", "mars", 902)
  end

  test "an unmarked waypoint may meet a genuine trader on approach" do
    {:ok, ships} =
      Traffic.launch_scheduled_trader(Traffic.seed(), "jupiter", "mars", 902)
    traffic = Traffic.advance(ships, 40_000)
    trader = Map.fetch!(traffic, "traffic:sol:cruise-902")
    {:ok, earth} = Sol.game_position_km("earth")

    voyage = %{
      status: :traveling,
      destination_id: nil,
      origin_position_km: earth,
      destination_position_km: trader.position_km,
      position_km: trader.position_km,
      distance_travelled_km: 1_000_000.0,
      travel_distance_km: 2_000_000.0
    }

    assert %{contact_id: "traffic:sol:cruise-902",
             origin_id: "jupiter", destination_id: "mars",
             kind: :independent_trader} = Encounters.nearest(traffic, voyage)
  end

  test "interception gradient expands only around real traffic" do
    {:ok, earth} = Sol.game_position_km("earth")
    near = %{earth | z: 400_000.0}
    remote = %{earth | z: 10_000_000.0}

    assert Encounters.encounter_radius_km(near) >
      Encounters.encounter_radius_km(remote)
    assert Encounters.nearest(%{}, %{
      status: :traveling, position_km: near,
      distance_travelled_km: 1.0, travel_distance_km: 2.0
    }) == nil
  end
end
