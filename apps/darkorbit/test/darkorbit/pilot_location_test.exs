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
