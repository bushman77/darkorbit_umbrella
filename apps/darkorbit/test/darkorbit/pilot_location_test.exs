defmodule Darkorbit.PilotLocationTest do
  use Darkorbit.DataCase, async: false

  import Darkorbit.AccountsFixtures
  alias Core.Universe.{Navigation, OrbitalEntry, Sol}
  alias Core.World.Position
  alias Darkorbit.{Fleet, PilotLocation}
  alias Darkorbit.PilotLocation.Checkpoint
  alias Darkorbit.Repo

  defp idle_at(body) do
    {:ok, position} = Sol.game_position_km(body)
    %{system_id: "sol", status: :idle,
      location_id: body, origin_id: body, destination_id: nil,
      arrival_origin_id: "earth", voyage_number: 3,
      free_flight: false, propulsion_mode: :conventional,
      position_km: position, origin_position_km: position,
      destination_position_km: nil, cruise_speed_km_s: 0.0,
      travel_distance_km: 0.0, distance_travelled_km: 0.0,
      elapsed_ms: 0, duration_ms: 0,
      pending_encounter: nil, tactical_encounter: nil}
  end

  test "Venus reconnect restores both authoritative map position and orientation" do
    account = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(account.id)
    voyage = idle_at("venus")
    {:ok, arrival} = OrbitalEntry.entry("earth", "venus", account.id, 3)

    assert :ok = PilotLocation.save_navigation(account.id, Navigation.Checkpoint.dump(voyage))
    assert PilotLocation.load_navigation(account.id)["location_id"] == "venus"

    position = %Position{
      x: arrival.position.x + 100,
      y: arrival.position.y + 120,
      z: arrival.position.z + 50}
    orientation = %{yaw: 0.2, pitch: -0.1, roll: 0.3}
    report = %{ship_instance_id: ship.id, position: position, attitude: orientation}
    assert :ok = PilotLocation.save_pose(account.id, "sol:venus", voyage, report)

    restored = PilotLocation.restore_entry(account.id, ship.id, arrival, 3)
    assert restored.position == position
    assert restored.attitude == orientation

    assert PilotLocation.restore_entry(account.id, ship.id, arrival, 4) == arrival
    assert PilotLocation.restore_entry(account.id, ship.id + 1, arrival, 3) == arrival
    {:ok, mars} = OrbitalEntry.entry("venus", "mars", account.id, 4)
    assert PilotLocation.restore_entry(account.id, ship.id, mars, 3) == mars

    assert :ok = PilotLocation.save_navigation(account.id, Navigation.Checkpoint.dump(voyage))
    saved = Repo.get_by!(Checkpoint, player_id: account.id)
    assert saved.pose_map_id == "sol:venus"
    assert saved.pose_position["z"] == position.z
  end

  test "rejects unsafe planetary poses and does not store transient flight-map coordinates" do
    account = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(account.id)
    voyage = idle_at("venus")
    {:ok, arrival} = OrbitalEntry.entry("earth", "venus", account.id, 3)
    assert :ok = PilotLocation.save_navigation(account.id, Navigation.Checkpoint.dump(voyage))

    center = OrbitalEntry.center("venus")
    report = %{ship_instance_id: ship.id,
      position: %Position{x: center.x, y: center.y, z: center.z},
      attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}}
    assert :ok = PilotLocation.save_pose(account.id, "sol:venus", voyage, report)
    assert PilotLocation.restore_entry(account.id, ship.id, arrival, 3) == arrival
    assert :ok = PilotLocation.save_pose(account.id, "sol:earth", voyage,
      %{report | position: arrival.position})
    assert PilotLocation.restore_entry(account.id, ship.id, arrival, 3) == arrival
    assert :ok = PilotLocation.save_pose(account.id, "sol:venus",
      %{voyage | status: :traveling}, %{report | position: arrival.position})
    assert PilotLocation.restore_entry(account.id, ship.id, arrival, 3) == arrival

    new_attitude = %{yaw: 0.1, pitch: 0.0, roll: 0.0}
    assert :ok = PilotLocation.save_pose(account.id, "sol:venus", voyage,
      %{report | position: arrival.position, attitude: new_attitude})
    assert PilotLocation.restore_entry(account.id, ship.id, arrival, 3).attitude ==
      new_attitude
  end

  test "manual SOL deep-space coordinates and heading persist without planet relocation" do
    account = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(account.id)
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    voyage = %{
      idle_at("earth") |
      status: :traveling, location_id: "earth", destination_id: "mars",
      free_flight: true, voyage_number: 7,
      origin_position_km: earth, destination_position_km: mars
    }
    # Construct a complete legal voyage using Core's public checkpoint.
    distance = :math.sqrt(:math.pow(mars.x - earth.x, 2) +
      :math.pow(mars.y - earth.y, 2))
    speed = Sol.cruise_speed_km_s()
    voyage = %{voyage | cruise_speed_km_s: speed,
      travel_distance_km: distance, duration_ms: ceil(distance / speed) * 1_000}

    entry = elem(Core.Universe.FreeFlightRegion.entry(account.id, voyage), 1)
    assert :ok = PilotLocation.save_navigation(account.id,
      Navigation.Checkpoint.dump(voyage))
    position = %Position{x: 13_510.0, y: 10_350.0, z: 322.0}
    attitude = %{yaw: 0.1, pitch: 0.2, roll: -0.12}
    report = %{ship_instance_id: ship.id, position: position, attitude: attitude}
    assert :ok = PilotLocation.save_pose(account.id, entry.map_id, voyage, report)
    restored = PilotLocation.restore_entry(account.id, ship.id, entry, 7)
    assert restored.position == position
    assert restored.attitude == attitude

    # Stale map/ship/voyage poses must never be reused.
    assert PilotLocation.restore_entry(account.id, ship.id, entry, 8) == entry
    assert PilotLocation.restore_entry(account.id, ship.id + 1, entry, 7) == entry
    {:ok, venus} = OrbitalEntry.entry("earth", "venus", account.id, 8)
    assert PilotLocation.restore_entry(account.id, ship.id, venus, 7) == venus

    # Crash or maliciously modified coordinates outside the map are rejected.
    bad = %{report | position: %Position{x: 25_000.0, y: 400.0, z: 0.0}}
    assert :ok = PilotLocation.save_pose(account.id, entry.map_id, voyage, bad)
    assert PilotLocation.restore_entry(account.id, ship.id, entry, 7) == restored
  end

  test "true deep-space waypoint remains stationary and restores its local cockpit" do
    account = player_account_fixture()
    {:ok, ship} = Fleet.get_active_ship(account.id)
    {:ok, earth} = Sol.game_position_km("earth")
    waypoint = %{earth | z: 1_000_000.0}
    idle = %{idle_at("earth") |
      location_id: nil, origin_id: nil, arrival_origin_id: nil,
      origin_position_km: waypoint, position_km: waypoint,
      voyage_number: 10}
    entry = elem(Core.Universe.FreeFlightRegion.entry(account.id, idle), 1)
    assert :ok = PilotLocation.save_navigation(account.id, Navigation.Checkpoint.dump(idle))
    assert PilotLocation.load_navigation(account.id)["location_id"] == nil
    report = %{ship_instance_id: ship.id,
      position: %Position{x: 12_200.0, y: 13_800.0, z: -400.0},
      attitude: %{yaw: -0.15, pitch: 0.0, roll: 0.1}}
    assert :ok = PilotLocation.save_pose(account.id, entry.map_id, idle, report)
    restored = PilotLocation.restore_entry(account.id, ship.id, entry, 10)
    assert restored.position == report.position
    assert restored.attitude == report.attitude
    assert :ok = PilotLocation.save_navigation(account.id, Navigation.Checkpoint.dump(idle))
    assert PilotLocation.restore_entry(account.id, ship.id, entry, 10) == restored
  end

  test "persisted navigation is keyed by pilot and retains transit checkpoints" do
    one = player_account_fixture()
    two = player_account_fixture()
    assert PilotLocation.load_navigation(one.id) == nil
    voyage = idle_at("mars")
    assert :ok = PilotLocation.save_navigation(one.id, Navigation.Checkpoint.dump(voyage))
    assert PilotLocation.load_navigation(one.id)["location_id"] == "mars"
    assert PilotLocation.load_navigation(two.id) == nil
    assert {:error, :invalid_checkpoint} =
      PilotLocation.save_navigation(one.id, %{"version" => 99})
  end
end
