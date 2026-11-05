defmodule Core.Universe.TrafficTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Sol
  alias Core.Universe.Traffic

  test "Scow exists as a separate merchant hull, not an automatic test-sector spawn" do
    assert {:ok, scow} = Core.NPC.Catalog.fetch("scow")
    assert scow.max_hull == 210
    assert scow.laser_damage == 10
    assert scow.movement_speed < Core.NPC.Catalog.fetch!("dart").movement_speed
    assert scow.spawn.map_id == "npc:templates"
    assert Enum.map(Core.NPC.Catalog.for_map("1-1"), & &1.id) == ["dart"]
  end

  test "a scheduled civilian freighter exists before any player arrives" do
    fleet = Traffic.seed()
    assert map_size(fleet) == 6
    vessel = Map.fetch!(fleet, "traffic:sol:meridian-01")
    assert vessel.id == "traffic:sol:meridian-01"
    assert vessel.kind == :commercial_freighter
    assert vessel.ship_class == "scow"
    assert vessel.disposition == :neutral
    assert vessel.faction_id == "sol_merchant_league"
    assert Core.Factions.name(vessel.faction_id) == "Solar Merchant League"
    assert vessel.purpose == :scheduled_delivery
    assert vessel.origin_id == "earth"
    assert vessel.destination_id == "mars"
    assert vessel.cargo == %{"industrial_machinery" => 120}
    assert vessel.state == :in_transit
    assert vessel.position_km == elem(Sol.game_position_km("earth"), 1)
  end

  test "six ships follow separate routes before any pilot creates an encounter" do
    traffic = Traffic.seed()
    assert map_size(traffic) == 6
    assert Enum.uniq(Map.keys(traffic)) == Map.keys(traffic)

    for vessel <- Map.values(traffic) do
      assert vessel.state == :in_transit
      assert vessel.duration_ms > 0
      assert vessel.cruise_speed_km_s > 0
      assert Sol.destination?(vessel.origin_id)
      assert Sol.destination?(vessel.destination_id)
      assert is_map(vessel.cargo)
      refute vessel.origin_id == vessel.destination_id
    end

    vesper = Map.fetch!(traffic, "traffic:sol:vesper-02")
    assert vesper.origin_id == "earth"
    assert vesper.destination_id == "venus"
    assert vesper.elapsed_ms > 0
    assert vesper.purpose == :express_delivery
    assert vesper.position_km != elem(Sol.game_position_km("earth"), 1)

    # All vessels are real, persistent server entities, not flyby spawns.
    moved = Traffic.advance(traffic, 90_000)
    assert Map.keys(moved) == Map.keys(traffic)
    assert moved["traffic:sol:vesper-02"].position_km != vesper.position_km
  end

  test "movement does not require a player, encounter or a new ship spawn" do
    original = Traffic.seed()
    freighter = Map.fetch!(original, "traffic:sol:meridian-01")
    moved = Traffic.advance(original, 30_000)
    assert Map.keys(moved) == Map.keys(original)
    moving = Map.fetch!(moved, "traffic:sol:meridian-01")
    assert moving.id == freighter.id
    assert moving.voyage_number == 1
    assert moving.elapsed_ms == 30_000
    assert moving.position_km != freighter.position_km
    assert moving.state == :in_transit
    assert Traffic.advance(original, 0) == original
  end

  test "the same freighter docks and returns with a meaningful return cargo" do
    freighter = Map.fetch!(Traffic.seed(), "traffic:sol:meridian-01")
    at_mars = Traffic.advance(Traffic.seed(), freighter.duration_ms)
    docked = Map.fetch!(at_mars, "traffic:sol:meridian-01")
    assert docked.state == :docked
    assert docked.location_id == "mars"
    assert docked.position_km == elem(Sol.game_position_km("mars"), 1)

    returning = Traffic.advance(at_mars, 45_000)
    homebound = Map.fetch!(returning, "traffic:sol:meridian-01")
    assert homebound.id == freighter.id
    assert homebound.state == :in_transit
    assert homebound.origin_id == "mars"
    assert homebound.destination_id == "earth"
    assert homebound.cargo == %{"refined_minerals" => 85}
    assert homebound.voyage_number == 2
    assert homebound.elapsed_ms == 0

    earth = Traffic.advance(returning, homebound.duration_ms)
      |> Map.fetch!("traffic:sol:meridian-01")
    assert earth.state == :docked
    assert earth.location_id == "earth"
    assert earth.voyage_number == 2
  end

  test "only nearby contacts appear; cargo is not leaked in passive scans" do
    fleet = Traffic.seed()
    {:ok, earth} = Sol.game_position_km("earth")
    contacts = Traffic.contacts(fleet, earth)
    assert [%{id: "traffic:sol:meridian-01", disposition: :neutral,
      faction_id: "sol_merchant_league", faction_name: "Solar Merchant League"}] = contacts
    refute Map.has_key?(hd(contacts), :cargo)
    refute Map.has_key?(hd(contacts), :manifest)

    # Move away from all outbound Earth lanes, not toward Vesper's courier route.
    remote = %{earth | x: earth.x - Traffic.sensor_radius_km() - 100_000.0}
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
    assert communication.faction_id == "sol_merchant_league"
    assert communication.faction_name == "Solar Merchant League"
    assert String.contains?(communication.message, "Solar Merchant League")
    assert communication.purpose == :scheduled_delivery
    assert is_binary(communication.message)
    assert fleet == Traffic.seed()
    assert {:error, :unknown_contact} = Traffic.hail(fleet, earth, nil)
  end

  test "procedural encounter is a genuine moving shared traffic vessel" do
    base = Traffic.seed()
    {:ok, traffic} =
      Traffic.launch_contact(base, "earth", "venus", 1, :independent_trader, 0.5)

    assert map_size(traffic) == map_size(base) + 1
    contact = Map.fetch!(traffic, "traffic:sol:cruise-1")
    assert contact.kind == :independent_trader
    assert contact.ship_class == "scow"
    assert contact.faction_name == nil or
      Core.Factions.name(contact.faction_id) != nil
    assert contact.origin_id == "venus"
    assert contact.destination_id == "earth"
    assert contact.state == :in_transit
    assert contact.procedural?
    assert contact.voyage_number == 1
    refute Map.has_key?(hd(Traffic.contacts(traffic, contact.position_km)), :cargo)

    moved = Traffic.advance(traffic, 1_000)
    assert moved[contact.id].position_km != contact.position_km

    {:ok, earth} = Sol.game_position_km("earth")
    assert {:error, :contact_out_of_range} = Traffic.hail(traffic, earth, contact.id)
    assert {:ok, established} = Traffic.hail_established(traffic, contact.id)
    assert established.id == contact.id
    assert moved[contact.id].lifetime_remaining_ms == 899_000
    assert Map.keys(base) |> Enum.all?(&Map.has_key?(moved, &1))

    # Once the ship's service window ends it is pruned, preserving the
    # permanent timetable instead of leaking one ship per finished voyage.
    later = Traffic.advance(traffic, 900_000)
    refute Map.has_key?(later, contact.id)
    assert map_size(later) == map_size(base)
  end

  test "procedural lane vessels use bounded server-owned identity and categories" do
    base = Traffic.seed()
    {:ok, patrol} = Traffic.launch_contact(base, "earth", "venus", 7, :patrol, 0.5)
    assert patrol["traffic:sol:cruise-7"].faction_id == "venus"
    assert patrol["traffic:sol:cruise-7"].kind == :patrol
    assert patrol["traffic:sol:cruise-7"].ship_class == "dart"

    {:ok, hostile} = Traffic.launch_contact(base, "earth", "venus", 8, :raider, 0.5)
    assert hostile["traffic:sol:cruise-8"].disposition == :hostile
    assert hostile["traffic:sol:cruise-8"].ship_class == "dart"
    assert {:error, :invalid_route} =
      Traffic.launch_contact(base, "earth", "earth", 9, :patrol, 0.5)
    assert {:error, :invalid_archetype} =
      Traffic.launch_contact(base, "earth", "venus", 9, :unknown, 0.5)
    assert {:error, :invalid_contact} =
      Traffic.launch_contact(base, "earth", "venus", 9, :patrol, 0.01)

    full =
      Enum.reduce(1..32, base, fn serial, traffic ->
        {:ok, updated} =
          Traffic.launch_contact(traffic, "earth", "venus", serial,
            :independent_trader, 0.5)
        updated
      end)
    assert {:error, :traffic_capacity} =
      Traffic.launch_contact(full, "earth", "venus", 33, :patrol, 0.5)
  end


  test "a settled retreat preserves hull, shields, route, cargo and vessel identity" do
    fleet = Traffic.seed()
    original = fleet["traffic:sol:meridian-01"]
    identity = %{contact_id: original.id, voyage_number: original.voyage_number,
                 encounter_id: "flyby:traffic:sol:meridian-01:1"}
    report = %{original.combat | hull: 180, shields: 20}

    assert {:ok, settled} = Traffic.settle(fleet, identity, report, :retreat)
    survivor = settled[original.id]
    assert survivor.combat == report
    assert survivor.cargo == original.cargo
    assert survivor.voyage_number == original.voyage_number
    assert survivor.origin_id == original.origin_id
    assert survivor.destination_id == original.destination_id
    assert survivor.state == :in_transit
    assert MapSet.member?(survivor.settled_encounters, identity.encounter_id)

    assert {:error, :already_settled} =
      Traffic.settle(settled, identity, report, :retreat)
    assert {:error, :stale_voyage} =
      Traffic.settle(settled,
        %{identity | voyage_number: 2, encounter_id: "stale-voyage"},
        %{report | hull: 170}, :retreat)

    moved = Traffic.advance(settled, 1_000)[original.id]
    assert moved.position_km != survivor.position_km
    assert moved.combat == report
  end

  test "forged heals, false victories, invalid identities and negative reports are rejected" do
    fleet = Traffic.seed()
    vessel = fleet["traffic:sol:vesper-02"]
    identity = %{contact_id: vessel.id, voyage_number: 1, encounter_id: "original-encounter"}

    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{vessel.combat | hull: 211}, :retreat)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{vessel.combat | shields: -1}, :retreat)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, vessel.combat, :victory)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{vessel.combat | status: :surrendered}, :escaped)
    assert {:error, :unknown_contact} =
      Traffic.settle(fleet, %{identity | contact_id: "forged"}, vessel.combat, :retreat)
  end

  test "surrender disables a real merchant without resetting or awarding its cargo" do
    fleet = Traffic.seed()
    vessel = fleet["traffic:sol:vesper-02"]
    identity = %{contact_id: vessel.id, voyage_number: 1, encounter_id: "held-courier"}
    report = %{vessel.combat | hull: 70, shields: 0, status: :surrendered}

    assert {:ok, settled} = Traffic.settle(fleet, identity, report, :surrender)
    disabled = settled[vessel.id]
    assert disabled.state == :disabled
    assert disabled.combat == report
    assert disabled.cargo == vessel.cargo
    assert Traffic.advance(settled, 90_000)[vessel.id] == disabled
    assert {:error, :vessel_unavailable} =
      Traffic.settle(settled, %{identity | encounter_id: "second"},
        %{report | hull: 60}, :surrender)

    # A pilot retreating after a captain has surrendered cannot magically
    # reactivate the surrendered merchant or reset its cargo manifest.
    assert {:ok, abandoned} =
      Traffic.settle(fleet, identity, report, :retreat)
    assert abandoned[vessel.id].state == :disabled
    assert abandoned[vessel.id].cargo == vessel.cargo
  end

  test "destroyed procedural raider with zero hull settles a verified victory" do
    {:ok, fleet} =
      Traffic.launch_contact(Traffic.seed(), "earth", "venus", 1, :raider, 0.5)

    raider = fleet["traffic:sol:cruise-1"]
    assert raider.combat == %{
      status: :alive, hull: 245, shields: 120,
      max_hull: 245, max_shields: 120
    }

    identity = %{
      contact_id: raider.id,
      voyage_number: raider.voyage_number,
      encounter_id: "flyby:traffic:sol:cruise-1:1"
    }
    destroyed = %{raider.combat | hull: 0, shields: 0, status: :destroyed}

    # A kill must not be rejected merely because destroyed means zero hull.
    assert {:ok, settled} = Traffic.settle(fleet, identity, destroyed, :victory)
    assert settled[raider.id].state == :destroyed
    assert settled[raider.id].combat == destroyed
    assert MapSet.member?(settled[raider.id].settled_encounters, identity.encounter_id)
    assert {:error, :already_settled} =
      Traffic.settle(settled, identity, destroyed, :victory)

    # Keep enforcing status/hull integrity and the original capacities.
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{destroyed | hull: 1}, :victory)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{destroyed | status: :alive}, :victory)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{destroyed | max_hull: 246}, :victory)
  end

  test "a destroyed vessel remains a tombstone and can never dock or reproduce its cargo" do
    fleet = Traffic.seed()
    vessel = fleet["traffic:sol:meridian-01"]
    identity = %{contact_id: vessel.id, voyage_number: 1, encounter_id: "combat-kill"}
    report = %{vessel.combat | hull: 0, shields: 0, status: :destroyed}
    assert {:ok, settled} = Traffic.settle(fleet, identity, report, :victory)

    destroyed = settled[vessel.id]
    assert destroyed.state == :destroyed
    assert destroyed.combat.status == :destroyed
    assert destroyed.cargo == vessel.cargo
    assert Traffic.advance(settled, vessel.duration_ms * 3)[vessel.id] == destroyed
    refute Enum.any?(Traffic.contacts(settled, vessel.position_km),
      &(&1.id == vessel.id))
    assert {:error, :unknown_contact} =
      Traffic.hail_established(settled, vessel.id)
    assert {:error, :already_settled} =
      Traffic.settle(settled, identity, report, :victory)
  end

  test "destroyed Corsair tactical report settles with zero hull and shields" do
    {:ok, fleet} =
      Traffic.launch_contact(Traffic.seed(), "earth", "venus", 1, :raider, 0.5)

    vessel = fleet["traffic:sol:cruise-1"]
    identity = %{
      contact_id: vessel.id,
      voyage_number: vessel.voyage_number,
      encounter_id: "flyby:traffic:sol:cruise-1:1"
    }
    report = %{vessel.combat | hull: 0, shields: 0, status: :destroyed}

    assert vessel.combat == %{
      status: :alive, hull: 245, shields: 120, max_hull: 245, max_shields: 120
    }

    assert {:ok, settled} = Traffic.settle(fleet, identity, report, :victory)
    corsair = settled[vessel.id]
    assert corsair.state == :destroyed
    assert corsair.combat == report
    assert MapSet.member?(corsair.settled_encounters, identity.encounter_id)

    assert {:error, :already_settled} =
      Traffic.settle(settled, identity, report, :victory)

    # A zero-hull ship cannot be reported alive, nor can victory be claimed
    # while the hull is still positive.
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{report | status: :alive}, :retreat)
    assert {:error, :invalid_combat_report} =
      Traffic.settle(fleet, identity, %{report | hull: 1}, :victory)
  end

  test "a leased procedural vessel cannot vanish or start a new voyage during combat" do
    {:ok, fleet} =
      Traffic.launch_contact(Traffic.seed(), "earth", "venus", 100,
        :independent_trader, 0.5)
    vessel = fleet["traffic:sol:cruise-100"]
    active = MapSet.new([vessel.id])

    held = Traffic.advance(fleet, 1_000_000, active)
    after_hold = held[vessel.id]
    assert after_hold != nil
    assert after_hold.voyage_number == vessel.voyage_number
    assert after_hold.state == :in_transit
    assert after_hold.elapsed_ms < after_hold.duration_ms
    assert after_hold.lifetime_remaining_ms == 1

    assert Traffic.advance(held, 1_000)[vessel.id] == nil
  end

end
