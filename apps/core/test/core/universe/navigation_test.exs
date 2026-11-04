defmodule Core.Universe.NavigationTest do
  use ExUnit.Case, async: true

  alias Core.Universe.Navigation

  setup do
    receiver = self()
    name = :"#{__MODULE__}.Test#{System.unique_integer([:positive])}"
    start_supervised!({Navigation,
      name: name, auto_tick: false, tick_ms: 1_000,
      event_sink: fn map_id, event, payload -> send(receiver, {map_id, event, payload}) end})
    %{server: name}
  end

  defp tick_and_resolve(server, player_id, count) do
    for _ <- 1..count do
      assert :ok = Navigation.tick(server)
      assert {:ok, navigation} = Navigation.snapshot(server, player_id)

      if navigation.pending_encounter do
        assert {:ok, %{cruise_paused: false}} =
          Navigation.resolve_encounter(server, player_id, navigation.pending_encounter.id, :continue)
      end
    end
  end

  test "a new pilot starts at Earth with no travel or combat encounter", %{server: server} do
    assert {:ok, state} = Navigation.snapshot(server, 11)
    assert state.system_id == "sol"
    assert state.location_id == "earth"
    assert state.arrival_origin_id == nil
    assert state.voyage_number == 0
    assert state.status == :idle
    assert state.destination_id == nil
    assert state.progress == 0.0
    assert "earth" in state.territory.faction_ids
    assert state.territory.status in [:controlled, :contested]
    assert :ok = Navigation.tick(server)
    assert {:ok, updated} = Navigation.snapshot(server, 11)
    assert updated.location_id == state.location_id
    assert updated.position_km == state.position_km
    # The freighter continues independently, so its contact distance changes.
    assert hd(updated.contacts).distance_km > hd(state.contacts).distance_km
  end

  test "validates destination and never trusts arbitrary solar names", %{server: server} do
    assert {:error, :invalid_solar_destination} =
      Navigation.set_course(server, 11, "sun")
    assert {:error, :invalid_solar_destination} =
      Navigation.set_course(server, 11, "sector-1-1")
    assert {:error, :already_at_destination} =
      Navigation.set_course(server, 11, "earth")
    assert {:error, :no_active_course} = Navigation.cancel_course(server, 11)
  end

  test "server-owned travel reaches Mars, then Pluto and isolates pilots", %{server: server} do
    assert {:ok, starting} = Navigation.snapshot(server, 22)
    assert {:ok, underway} = Navigation.set_course(server, 11, "mars")
    assert underway.origin_id == "earth"
    assert underway.voyage_number == 1
    assert underway.destination_id == "mars"
    assert underway.status == :traveling
    assert underway.remaining_ms > 0
    assert underway.propulsion_mode == :interplanetary_cruise
    assert underway.cruise_speed_km_s > 0
    assert underway.travel_distance_km > 0
    assert underway.position_km == underway.origin_position_km
    assert_receive {"sol", :solar_navigation_updated,
                    %{player_id: 11, navigation: %{destination_id: "mars"}}}
    assert {:error, :already_traveling} = Navigation.set_course(server, 11, "pluto")
    assert :ok = Navigation.tick(server)
    assert {:ok, step} = Navigation.snapshot(server, 11)
    assert step.progress > 0.0
    assert step.progress < 1.0
    assert step.elapsed_ms == 1_000
    assert step.distance_travelled_km == underway.cruise_speed_km_s
    assert step.position_km != underway.position_km
    tick_and_resolve(server, 11, ceil(underway.duration_ms / 1_000))
    assert {:ok, arrived} = Navigation.snapshot(server, 11)
    assert arrived.location_id == "mars"
    assert arrived.arrival_origin_id == "earth"
    assert arrived.voyage_number == 1
    assert arrived.status == :idle
    assert arrived.propulsion_mode == :conventional
    assert arrived.destination_id == nil
    assert {:ok, mars_position} = Core.Universe.Sol.game_position_km("mars")
    assert arrived.position_km == mars_position
    assert {:ok, waiting} = Navigation.snapshot(server, 22)
    assert waiting.location_id == starting.location_id
    assert waiting.position_km == starting.position_km
    assert waiting.status == :idle
    assert {:ok, %{destination_id: "pluto", voyage_number: 2}} =
      Navigation.set_course(server, 11, "pluto")
  end

  test "Venus approach projects an increasingly large real-radius planet without affecting flight", %{server: server} do
    {:ok, earth} = Navigation.snapshot(server, 1_260)
    assert earth.planetary_view.body_id == "earth"
    assert earth.planetary_view.stage == :orbital_preview
    assert earth.planetary_view.angular_diameter_deg == 65.0
    assert earth.planetary_view.visual_only

    {:ok, departure} = Navigation.set_course(server, 1_260, "venus")
    assert departure.planetary_view.body_id == "venus"
    assert departure.planetary_view.stage == :approach_preview
    assert departure.planetary_view.angular_diameter_deg == 1.5
    assert departure.position_km == departure.origin_position_km

    midpoint = div(departure.duration_ms, 2_000)
    tick_and_resolve(server, 1_260, midpoint)
    {:ok, approaching} = Navigation.snapshot(server, 1_260)
    assert approaching.planetary_view.angular_diameter_deg >
      departure.planetary_view.angular_diameter_deg
    assert approaching.planetary_view.angular_diameter_deg < 65.0
    assert approaching.status == :traveling

    tick_and_resolve(server, 1_260, ceil(departure.duration_ms / 1_000))
    {:ok, arrived} = Navigation.snapshot(server, 1_260)
    assert arrived.status == :idle
    assert arrived.location_id == "venus"
    assert arrived.planetary_view.body_id == "venus"
    assert arrived.planetary_view.stage == :orbital_preview
    assert arrived.planetary_view.angular_diameter_deg == 65.0
    assert arrived.position_km == elem(Core.Universe.Sol.game_position_km("venus"), 1)
  end

  test "contact identity and traffic progression persist across disconnected pilots", %{server: server} do
    assert {:ok, initial} = Navigation.snapshot(server, 11)
    assert [%{id: id, origin_id: "earth", destination_id: "mars"}] = initial.contacts
    start_distance = hd(initial.contacts).distance_km

    for _ <- 1..8, do: :ok = Navigation.tick(server)
    assert {:ok, later} = Navigation.snapshot(server, 77)
    assert [%{id: ^id, distance_km: distance}] = later.contacts
    assert distance > start_distance

    assert {:ok, after_return} = Navigation.snapshot(server, 11)
    assert hd(after_return.contacts).id == id
  end

  test "an authenticated in-range pilot can hail civilian cargo without hijacking its route", %{server: server} do
    assert {:ok, before} = Navigation.snapshot(server, 101)
    assert [%{id: ship_id}] = before.contacts
    assert {:ok, hail} = Navigation.hail(server, 101, ship_id)
    assert hail.cargo == %{"industrial_machinery" => 120}
    assert hail.disposition == :neutral
    assert {:error, :unknown_contact} = Navigation.hail(server, 101, "traffic:sol:fake")

    assert :ok = Navigation.tick(server)
    assert {:ok, after_tick} = Navigation.snapshot(server, 101)
    assert hd(after_tick.contacts).distance_km > hd(before.contacts).distance_km
  end

  test "Earth-to-Venus cruise holds at a real courier, announces once and supports hail", %{server: server} do
    assert {:ok, %{encounter: nil}} = Navigation.set_course(server, 910, "venus")

    for _ <- 1..109, do: assert(:ok = Navigation.tick(server))
    assert {:ok, crossing} = Navigation.snapshot(server, 910)
    assert crossing.status == :traveling
    assert %{call_sign: "Vesper-02", contact_id: vessel_id,
             mode: :strategic_flyby, distance_km: separation} = crossing.pending_encounter
    assert crossing.cruise_paused
    assert crossing.elapsed_ms < 109_000
    assert separation < 650_000

    assert_receive {"sol", :solar_encounter_started,
      %{player_id: 910, encounter: %{contact_id: ^vessel_id,
                                      call_sign: "Vesper-02"}}}
    assert {:ok, reply} = Navigation.hail(server, 910, vessel_id)
    assert reply.call_sign == "Vesper-02"
    assert reply.cargo == %{"medical_supplies" => 48}

    # A contact is a real vessel and is never duplicated or removed merely
    # because the pilot encounters it.
    {:ok, other_player} = Navigation.snapshot(server, 911)
    assert other_player.status == :idle
    refute other_player.encounter
    for _ <- 1..5, do: assert(:ok = Navigation.tick(server))
    refute_receive {"sol", :solar_encounter_started, %{player_id: 910}}, 0

    assert {:ok, paused} = Navigation.snapshot(server, 910)
    assert paused.cruise_paused
    assert paused.elapsed_ms == crossing.elapsed_ms
    assert paused.position_km == crossing.position_km

    assert {:ok, resumed} = Navigation.resolve_encounter(
      server, 910, crossing.pending_encounter.id, :continue)
    refute resumed.cruise_paused
    assert resumed.pending_encounter == nil

    for _ <- 1..35, do: assert(:ok = Navigation.tick(server))
    assert {:ok, departed} = Navigation.snapshot(server, 910)
    assert departed.pending_encounter == nil
    assert departed.status == :traveling
    assert departed.elapsed_ms > resumed.elapsed_ms
    refute_receive {"sol", :solar_encounter_started, %{player_id: 910}}, 0
  end

  test "director labels an authoritative hostile close pass and holds cruise" do
    receiver = self()
    name = :"#{__MODULE__}.Hostile#{System.unique_integer([:positive])}"
    traffic =
      Core.Universe.Traffic.seed()
      |> Map.update!("traffic:sol:vesper-02", &%{&1 | disposition: :hostile})

    start_supervised!(%{
      id: name,
      start: {Navigation, :start_link, [[
        name: name, auto_tick: false, tick_ms: 1_000, traffic: traffic,
        event_sink: fn map_id, event, payload ->
          send(receiver, {map_id, event, payload})
        end
      ]]}
    })

    assert {:ok, _} = Navigation.set_course(name, 991, "venus")
    for _ <- 1..109, do: assert(:ok = Navigation.tick(name))

    assert {:ok, underway} = Navigation.snapshot(name, 991)
    assert underway.status == :traveling
    assert %{contact_id: "traffic:sol:vesper-02",
             classification: :hostile_contact, mode: :strategic_flyby} =
      underway.pending_encounter
    assert underway.cruise_paused
    refute Map.has_key?(underway, :pilot_reputations)
    assert_receive {"sol", :solar_encounter_started,
      %{player_id: 991, encounter: %{classification: :hostile_contact}}}

    assert {:ok, other} = Navigation.snapshot(name, 992)
    assert other.status == :idle
    assert other.encounter == nil
  end


  test "encounter hold is per pilot, survives a snapshot, and rejects invalid decisions",
       %{server: server} do
    assert {:ok, _} = Navigation.set_course(server, 731, "venus")
    assert {:ok, _} = Navigation.set_course(server, 732, "mars")

    for _ <- 1..85, do: assert(:ok = Navigation.tick(server))
    assert {:ok, pilot} = Navigation.snapshot(server, 731)
    assert pilot.cruise_paused
    assert %{id: encounter_id, contact_id: contact_id} = pilot.pending_encounter
    assert contact_id == "traffic:sol:vesper-02"

    assert {:error, :encounter_decision_required} =
      Navigation.cancel_course(server, 731)
    # Pilot 732 independently crossed another real vessel on the Mars route.
    # A different pilot's encounter ID must not resolve that contact.
    assert {:ok, other_before} = Navigation.snapshot(server, 732)
    assert %{id: other_encounter_id} = other_before.pending_encounter
    assert other_encounter_id != encounter_id
    assert {:error, :encounter_mismatch} =
      Navigation.resolve_encounter(server, 732, encounter_id, :continue)
    assert {:error, :encounter_mismatch} =
      Navigation.resolve_encounter(server, 731, "forged:contact", :continue)
    assert {:error, :invalid_encounter_choice} =
      Navigation.resolve_encounter(server, 731, encounter_id, :fight)

    assert {:ok, %{cruise_paused: false}} =
      Navigation.resolve_encounter(server, 732, other_encounter_id, :continue)
    for _ <- 1..10, do: assert(:ok = Navigation.tick(server))
    assert {:ok, held} = Navigation.snapshot(server, 731)
    assert held.position_km == pilot.position_km
    assert held.elapsed_ms == pilot.elapsed_ms
    assert held.remaining_ms == pilot.remaining_ms
    assert held.pending_encounter.id == encounter_id

    assert {:ok, other_after} = Navigation.snapshot(server, 732)
    assert other_after.elapsed_ms > other_before.elapsed_ms
    assert other_after.position_km != other_before.position_km
    # Pilot 731 remains held even though pilot 732 resolved its own contact.

    assert {:ok, continued} =
      Navigation.resolve_encounter(server, 731, encounter_id, :continue)
    assert continued.status == :traveling
    assert continued.pending_encounter == nil
    assert continued.cruise_paused == false
    assert {:error, :no_pending_encounter} =
      Navigation.resolve_encounter(server, 731, encounter_id, :continue)
    assert :ok = Navigation.tick(server)
    assert {:ok, moving} = Navigation.snapshot(server, 731)
    assert moving.elapsed_ms == pilot.elapsed_ms + 1_000
  end

  test "simultaneous pilots advance the same one-second clock with different routes", %{server: server} do
    assert {:ok, mars} = Navigation.set_course(server, 101, "mars")
    assert {:ok, pluto} = Navigation.set_course(server, 202, "pluto")
    assert mars.duration_ms != pluto.duration_ms
    assert :ok = Navigation.tick(server)
    assert {:ok, a} = Navigation.snapshot(server, 101)
    assert {:ok, b} = Navigation.snapshot(server, 202)
    assert a.elapsed_ms == 1_000
    assert b.elapsed_ms == 1_000
    assert a.distance_travelled_km == b.distance_travelled_km
    assert a.progress > b.progress
  end

  test "aborting a cruise returns to the origin in this sector-free prototype", %{server: server} do
    assert {:ok, _state} = Navigation.set_course(server, 11, "neptune")
    assert :ok = Navigation.tick(server)
    assert {:ok, canceled} = Navigation.cancel_course(server, 11)
    assert canceled.location_id == "earth"
    assert canceled.status == :idle
    assert canceled.destination_id == nil
    assert {:error, :no_active_course} = Navigation.cancel_course(server, 11)
  end

  test "jurisdiction follows server-owned SOL cruise positions", %{server: server} do
    assert {:ok, start} = Navigation.snapshot(server, 503)
    assert {:ok, initial} = Core.Universe.Territory.classify(start.position_km)
    assert start.territory.status == initial.status
    assert start.territory.faction_ids ==
             Enum.map(initial.claims, & &1.faction_id)

    assert {:ok, _route} = Navigation.set_course(server, 503, "mars")

    for _ <- 1..5 do
      assert :ok = Navigation.tick(server)
      assert {:ok, underway} = Navigation.snapshot(server, 503)
      assert underway.status == :traveling
      assert {:ok, expected} = Core.Universe.Territory.classify(underway.position_km)
      assert underway.territory.status == expected.status
      assert underway.territory.faction_ids ==
               Enum.map(expected.claims, & &1.faction_id)
      refute Map.has_key?(underway, :reputations)
      refute Map.has_key?(underway, :patrols)
    end
  end

  test "procedural encounter intersects Earth-to-Venus despite an empty existing fleet" do
    receiver = self()
    name = :"#{__MODULE__}.Procedural#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start: {Navigation, :start_link, [[
        name: name,
        auto_tick: false,
        tick_ms: 1_000,
        traffic: %{},
        procedural_contact_chance: 1.0,
        event_sink: fn map_id, event, payload ->
          send(receiver, {map_id, event, payload})
        end
      ]]}
    })

    assert {:ok, %{status: :traveling, pending_encounter: nil}} =
      Navigation.set_course(name, 814, "venus")

    # A real, newly launched vessel belongs to the shared SOL simulation.
    world_state = :sys.get_state(name)
    assert map_size(world_state.traffic) == 1
    contact = world_state.traffic["traffic:sol:cruise-1"]
    assert contact.state == :in_transit
    assert contact.origin_id == "venus"
    assert contact.destination_id == "earth"

    for _ <- 1..100, do: assert(:ok = Navigation.tick(name))
    assert {:ok, holding} = Navigation.snapshot(name, 814)
    assert holding.cruise_paused
    assert %{contact_id: "traffic:sol:cruise-1", id: encounter_id,
             mode: :strategic_flyby} = holding.pending_encounter
    assert holding.progress > 0.05
    assert holding.progress < 0.95

    assert_receive {"sol", :solar_encounter_started,
      %{player_id: 814, encounter: %{id: ^encounter_id}}}
    # While this specific decision is held, the server preserves the
    # comms channel even as the traffic contact moves out of sensor range.
    assert {:ok, hail} = Navigation.hail(name, 814, "traffic:sol:cruise-1")
    assert hail.id == "traffic:sol:cruise-1"
    assert {:error, :unknown_contact} =
      Navigation.hail(name, 814, "traffic:sol:cruise-999")

    {:ok, other} = Navigation.snapshot(name, 815)
    assert other.status == :idle
    refute other.pending_encounter

    assert {:ok, %{cruise_paused: false}} =
      Navigation.resolve_encounter(name, 814, encounter_id, :continue)
    assert :ok = Navigation.tick(name)
    assert {:ok, resumed} = Navigation.snapshot(name, 814)
    assert resumed.elapsed_ms == holding.elapsed_ms + 1_000
  end

  test "procedural spawn is optional for isolated tests and never client-supplied" do
    receiver = self()
    name = :"#{__MODULE__}.NoSpawn#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start: {Navigation, :start_link, [[
        name: name,
        auto_tick: false,
        tick_ms: 1_000,
        traffic: %{},
        procedural_contact_chance: 0.0,
        event_sink: fn map_id, event, payload ->
          send(receiver, {map_id, event, payload})
        end
      ]]}
    })

    assert {:ok, _} = Navigation.set_course(name, 812, "venus")
    assert :sys.get_state(name).traffic == %{}
    for _ <- 1..100, do: assert(:ok = Navigation.tick(name))
    assert {:ok, voyage} = Navigation.snapshot(name, 812)
    assert voyage.pending_encounter == nil
    assert voyage.cruise_paused == false
  end


  test "two pilots cannot claim the same merchant; settlement carries damage into the next fight",
       %{server: server} do
    assert {:ok, _} = Navigation.set_course(server, 1_100, "venus")
    assert {:ok, _} = Navigation.set_course(server, 1_101, "venus")
    for _ <- 1..85, do: assert(:ok = Navigation.tick(server))

    {:ok, first} = Navigation.snapshot(server, 1_100)
    {:ok, second} = Navigation.snapshot(server, 1_101)
    first_id = first.pending_encounter.id
    second_id = second.pending_encounter.id
    contact_id = "traffic:sol:vesper-02"
    assert first.pending_encounter.contact_id == contact_id
    assert second.pending_encounter.contact_id == contact_id

    assert {:ok, %{tactical_encounter: tactical}} =
      Navigation.enter_tactical(server, 1_100, first_id)
    assert tactical.contact_id == contact_id
    assert tactical.voyage_number == 1
    assert tactical.combat == :sys.get_state(server).traffic[contact_id].combat
    assert {:error, :vessel_engaged} =
      Navigation.enter_tactical(server, 1_101, second_id)
    assert {:error, :tactical_report_required} =
      Navigation.finish_tactical(server, 1_100, first_id, :retreat)

    report = %{contact_id: contact_id, encounter_id: first_id, voyage_number: 1,
      combat: %{tactical.combat | hull: 175, shields: 18}}

    assert {:error, :tactical_report_mismatch} =
      Navigation.finish_tactical(server, 1_100, first_id, :retreat,
        %{report | contact_id: "forged"})

    assert {:ok, %{cruise_paused: false}} =
      Navigation.finish_tactical(server, 1_100, first_id, :retreat, report)
    assert {:ok, %{tactical_encounter: nil}} =
       Navigation.finish_tactical(server, 1_100, first_id, :retreat, report)
    assert :sys.get_state(server).tactical_claims == %{}
    assert :sys.get_state(server).traffic[contact_id].combat == report.combat

    assert {:ok, %{tactical_encounter: next_tactical}} =
      Navigation.enter_tactical(server, 1_101, second_id)
    assert next_tactical.combat == report.combat
    assert {:ok, _} =
      Navigation.finish_tactical(server, 1_101, second_id, :rollback)
    assert :sys.get_state(server).tactical_claims == %{}
  end

  test "a destroyed merchant cannot be intercepted again by another held pilot",
       %{server: server} do
    assert {:ok, _} = Navigation.set_course(server, 1_120, "venus")
    assert {:ok, _} = Navigation.set_course(server, 1_121, "venus")
    for _ <- 1..85, do: assert(:ok = Navigation.tick(server))
    {:ok, first} = Navigation.snapshot(server, 1_120)
    {:ok, second} = Navigation.snapshot(server, 1_121)
    id = first.pending_encounter.id
    assert second.pending_encounter.id == id

    assert {:ok, %{tactical_encounter: tactical}} =
      Navigation.enter_tactical(server, 1_120, id)
    report = %{
      contact_id: tactical.contact_id, encounter_id: id,
      voyage_number: tactical.voyage_number,
      combat: %{tactical.combat | hull: 0, shields: 0, status: :destroyed}
    }
    assert {:ok, %{pending_encounter: nil}} =
      Navigation.finish_tactical(server, 1_120, id, :victory, report)
    assert {:error, :vessel_unavailable} =
      Navigation.enter_tactical(server, 1_121, id)
    assert {:ok, %{pending_encounter: nil}} =
      Navigation.resolve_encounter(server, 1_121, id, :continue)
    assert :sys.get_state(server).traffic[tactical.contact_id].state == :destroyed
  end

end
