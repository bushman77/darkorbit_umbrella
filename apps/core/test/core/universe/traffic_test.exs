defmodule Core.Universe.TrafficTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Sol
  alias Core.Universe.Traffic

  test "a scheduled civilian freighter exists before any player arrives" do
    fleet = Traffic.seed()
    assert map_size(fleet) == 1
    [vessel] = Map.values(fleet)
    assert vessel.id == "traffic:sol:meridian-01"
    assert vessel.kind == :commercial_freighter
    assert vessel.disposition == :neutral
    assert vessel.purpose == :scheduled_delivery
    assert vessel.origin_id == "earth"
    assert vessel.destination_id == "mars"
    assert vessel.cargo == %{"industrial_machinery" => 120}
    assert vessel.state == :in_transit
    assert vessel.position_km == elem(Sol.game_position_km("earth"), 1)
  end

  test "movement does not require a player, encounter or a new ship spawn" do
    original = Traffic.seed()
    [freighter] = Map.values(original)
    moved = Traffic.advance(original, 30_000)
    assert Map.keys(moved) == Map.keys(original)
    [moving] = Map.values(moved)
    assert moving.id == freighter.id
    assert moving.voyage_number == 1
    assert moving.elapsed_ms == 30_000
    assert moving.position_km != freighter.position_km
    assert moving.state == :in_transit
    assert Traffic.advance(original, 0) == original
  end

  test "the same freighter docks and returns with a meaningful return cargo" do
    [freighter] = Map.values(Traffic.seed())
    at_mars = Traffic.advance(Traffic.seed(), freighter.duration_ms)
    [docked] = Map.values(at_mars)
    assert docked.state == :docked
    assert docked.location_id == "mars"
    assert docked.position_km == elem(Sol.game_position_km("mars"), 1)

    returning = Traffic.advance(at_mars, 45_000)
    [homebound] = Map.values(returning)
    assert homebound.id == freighter.id
    assert homebound.state == :in_transit
    assert homebound.origin_id == "mars"
    assert homebound.destination_id == "earth"
    assert homebound.cargo == %{"refined_minerals" => 85}
    assert homebound.voyage_number == 2
    assert homebound.elapsed_ms == 0

    [earth] = Traffic.advance(returning, homebound.duration_ms) |> Map.values()
    assert earth.state == :docked
    assert earth.location_id == "earth"
    assert earth.voyage_number == 2
  end

  test "only nearby contacts appear; cargo is not leaked in passive scans" do
    fleet = Traffic.seed()
    {:ok, earth} = Sol.game_position_km("earth")
    contacts = Traffic.contacts(fleet, earth)
    assert [%{id: "traffic:sol:meridian-01", disposition: :neutral}] = contacts
    refute Map.has_key?(hd(contacts), :cargo)
    refute Map.has_key?(hd(contacts), :manifest)

    remote = %{earth | x: earth.x + Traffic.sensor_radius_km() + 100_000.0}
    assert Traffic.contacts(fleet, remote) == []
    assert {:error, :contact_out_of_range} =
      Traffic.hail(fleet, remote, "traffic:sol:meridian-01")
    assert {:error, :unknown_contact} = Traffic.hail(fleet, earth, "forged:ship")
  end

  test "hailing reveals purpose and manifest without changing or stopping transit" do
    fleet = Traffic.seed()
    {:ok, earth} = Sol.game_position_km("earth")
    assert {:ok, communication} = Traffic.hail(fleet, earth, "traffic:sol:meridian-01")
    assert communication.cargo == %{"industrial_machinery" => 120}
    assert communication.disposition == :neutral
    assert communication.purpose == :scheduled_delivery
    assert is_binary(communication.message)
    assert fleet == Traffic.seed()
    assert {:error, :unknown_contact} = Traffic.hail(fleet, earth, nil)
  end
end
