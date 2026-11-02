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
    assert :ok = Navigation.tick(server)
    assert {:ok, ^state} = Navigation.snapshot(server, 11)
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
    assert_receive {"1-1", :solar_navigation_updated,
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
    assert {:ok, ^starting} = Navigation.snapshot(server, 22)
    assert {:ok, %{destination_id: "pluto"}} =
      Navigation.set_course(server, 11, "pluto")
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
end

