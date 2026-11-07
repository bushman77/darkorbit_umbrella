defmodule Core.Universe.SpaceBasesNavigationTest do
  use ExUnit.Case, async: true

  alias Core.Universe.{Navigation, OrbitalEntry, Sol, SpaceBases, Traffic}

  defp server(opts) do
    unique = :"#{__MODULE__}.#{System.unique_integer([:positive])}"
    start_supervised!({Navigation,
      Keyword.merge([
        name: unique, auto_tick: false, tick_ms: 1_000,
        event_sink: fn _map_id, _event, _payload -> :ok end
      ], opts)})
    unique
  end

  test "a planetary map publishes the fixed base outside its physical collision exclusion" do
    for planet <- Sol.planets() do
      site = OrbitalEntry.space_base(planet.id)
      assert site.id == "sol:base:" <> planet.id
      assert site.refinery_id == "sol:refinery:" <> planet.id
      assert site.model == :orbital_refinery_v1
      assert site.berth_count == 3

      region = Enum.find(OrbitalEntry.planet_maps(), &(&1.id == "sol:" <> planet.id))
      position = site.position_3d
      centre = region.planet.center
      gap = :math.sqrt(:math.pow(position.x - centre.x, 2) +
        :math.pow(position.y - centre.y, 2) +
        :math.pow(position.z - centre.z, 2))
      assert gap > region.planet.exclusion_radius
      assert position.x > 0 and position.x < region.width
      assert position.y > 0 and position.y < region.height
    end

    assert OrbitalEntry.space_base("sun") == nil
    assert OrbitalEntry.space_base("unregistered") == nil
  end

  test "live SOL clock docks a real Meridian and publishes local berth occupancy" do
    ship = Traffic.seed()["traffic:sol:meridian-01"]
    server = server(traffic: %{ship.id => ship}, tick_ms: ship.duration_ms)

    assert {:ok, earth} = Navigation.snapshot(server, 700)
    assert earth.space_base.id == "sol:base:earth"
    assert earth.space_base.occupied_berths == 0

    assert :ok = Navigation.tick(server)
    state = :sys.get_state(server)
    assert state.traffic[ship.id].state == :docked
    assert state.traffic[ship.id].location_id == "mars"
    assert SpaceBases.public(state.bases, "mars").occupied_berths == 1
    assert state.bases["mars"].stock["industrial_machinery"] == 120
    assert state.traffic[ship.id].cargo == %{"refined_minerals" => 85}
  end

  test "the SOL scheduled departure withdraws its cargo from the real Earth refinery" do
    server = server(traffic: %{}, scheduled_trader_interval_ms: 1_000)
    before = :sys.get_state(server).bases["earth"].stock["industrial_parts"]

    assert :ok = Navigation.tick(server)
    state = :sys.get_state(server)
    assert map_size(state.traffic) == 1
    trader = state.traffic["traffic:sol:cruise-1"]
    assert trader.origin_id == "earth"
    assert trader.cargo == %{"industrial_parts" => 32}
    assert state.bases["earth"].stock["industrial_parts"] == before - 32
  end
end
