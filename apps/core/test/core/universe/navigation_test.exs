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

  test "a new pilot starts at Earth with no travel or combat encounter", %{server: server} do
    assert {:ok, state} = Navigation.snapshot(server, 11)
    assert state.system_id == "sol"
    assert state.location_id == "earth"
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
    for _ <- 1..ceil(underway.duration_ms / 1_000), do: :ok = Navigation.tick(server)
    assert {:ok, arrived} = Navigation.snapshot(server, 11)
    assert arrived.location_id == "mars"
    assert arrived.status == :idle
    assert arrived.propulsion_mode == :conventional
    assert arrived.destination_id == nil
    assert {:ok, mars_position} = Core.Universe.Sol.game_position_km("mars")
    assert arrived.position_km == mars_position
    assert {:ok, waiting} = Navigation.snapshot(server, 22)
    assert waiting.location_id == starting.location_id
    assert waiting.position_km == starting.position_km
    assert waiting.status == :idle
    assert {:ok, %{destination_id: "pluto"}} =
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
    for _ <- 1..midpoint, do: :ok = Navigation.tick(server)
    {:ok, approaching} = Navigation.snapshot(server, 1_260)
    assert approaching.planetary_view.angular_diameter_deg >
      departure.planetary_view.angular_diameter_deg
    assert approaching.planetary_view.angular_diameter_deg < 65.0
    assert approaching.status == :traveling

    for _ <- 1..ceil(departure.duration_ms / 1_000), do: :ok = Navigation.tick(server)
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
end
