defmodule Darkorbit.WorldTest do
  use Darkorbit.DataCase

  import Darkorbit.AccountsFixtures

  alias Darkorbit.World

  test "connects an active ship, publishes state, and moves it headlessly" do
    account = player_account_fixture()
    assert :ok = World.subscribe()
    assert {:ok, session} = World.connect(account.id, 1)

    on_exit(fn -> World.disconnect(session.id) end)

    assert_receive {:entity_joined, %{id: entity_id, position: %{x: 1_000.0, y: 1_000.0}}}
    assert entity_id == account.id

    assert {:ok, %{position: %{x: 1_000.0, y: 1_000.0}}} =
             World.move(session.id, %{x: 1_064.0, y: 1_000.0})

    assert_receive {:movement_started, %{destination: %{x: 1_064.0, y: 1_000.0}}}

    assert {:ok, before_tick} = World.snapshot()
    first_tick_number = before_tick.tick + 1
    assert {:ok, first_tick} = World.tick()
    %{position: %{x: first_x}} = Enum.find(first_tick.entities, &(&1.kind == :player))
    assert_in_delta first_x, 1_032.0, 0.000_001
    assert_receive {:world_state, %{tick: ^first_tick_number}}

    second_tick_number = first_tick_number + 1
    assert {:ok, second_tick} = World.tick()
    player = Enum.find(second_tick.entities, &(&1.kind == :player))
    assert player.position == %{x: 1_064.0, y: 1_000.0}
    assert player.destination == nil
    assert_receive {:world_state, %{tick: ^second_tick_number}}
  end

  test "Venus orbital XYZ and heading survive a real authenticated disconnect/rejoin" do
    account = player_account_fixture()
    {:ok, ship} = Darkorbit.Fleet.get_active_ship(account.id)
    navigation_server = Module.concat(Core.World.SessionManager, Core.Universe.Navigation)
    {:ok, venus} = Core.Universe.Sol.game_position_km("venus")

    saved_navigation = %{
      "version" => 1, "status" => "idle", "location_id" => "venus",
      "origin_id" => "venus", "destination_id" => nil,
      "arrival_origin_id" => "earth", "voyage_number" => 1,
      "free_flight" => false,
      "position_km" => venus, "origin_position_km" => venus,
      "destination_position_km" => nil, "cruise_speed_km_s" => 0.0,
      "travel_distance_km" => 0.0, "distance_travelled_km" => 0.0,
      "elapsed_ms" => 0, "duration_ms" => 0
    }
    assert :ok = Darkorbit.PilotLocation.save_navigation(account.id, saved_navigation)
    assert {:ok, live_voyage} =
      Core.Universe.Navigation.Checkpoint.load(saved_navigation)

    :sys.replace_state(navigation_server, fn state ->
      %{state | voyages: Map.put(state.voyages, account.id, live_voyage)}
    end)

    {:ok, entry} = Core.Universe.OrbitalEntry.entry("earth", "venus", account.id, 1)
    saved_position = %Core.World.Position{
      x: entry.position.x + 45.0,
      y: entry.position.y - 10.0,
      z: entry.position.z + 25.0
    }
    heading = %{yaw: 0.15, pitch: 0.05, roll: -0.15}
    assert :ok = Darkorbit.PilotLocation.save_pose(account.id, "sol:venus", live_voyage, %{
      ship_instance_id: ship.id, position: saved_position, attitude: heading
    })

    assert {:ok, first} = World.connect(account.id)
    assert first.map_id == "sol:venus"
    assert {:ok, snapshot} = World.snapshot("sol:venus")
    pilot = Enum.find(snapshot.entities, &(&1.id == account.id))
    assert pilot.position_3d == Map.from_struct(saved_position)
    assert pilot.attitude == heading
    assert :ok = World.disconnect(first.id)

    assert {:ok, second} = World.connect(account.id)
    on_exit(fn -> World.disconnect(second.id) end)
    assert second.map_id == "sol:venus"
    assert {:ok, restored} = World.snapshot("sol:venus")
    returned = Enum.find(restored.entities, &(&1.id == account.id))
    assert returned.position_3d == Map.from_struct(saved_position)
    assert returned.attitude == heading
  end

  test "reconnect in manual SOL free flight retains the same local XYZ and heading" do
    account = player_account_fixture()
    {:ok, ship} = Darkorbit.Fleet.get_active_ship(account.id)
    server = Module.concat(Core.World.SessionManager, Core.Universe.Navigation)
    {:ok, starting} = Core.Universe.Navigation.set_course(server, account.id, "mars")
    assert {:ok, manual} = Core.Universe.Navigation.enter_free_flight(server, account.id)
    assert manual.status == :traveling
    assert manual.free_flight
    assert manual.voyage_number == starting.voyage_number

    {:ok, first} = World.connect(account.id)
    assert first.map_id == Core.Universe.FreeFlightRegion.map_id(account.id)
    assert {:ok, initial} = World.snapshot(first.map_id)
    pilot = Enum.find(initial.entities, &(&1.id == account.id))
    assert pilot

    position = %Core.World.Position{x: 13_650.0, y: 14_200.0, z: 625.0}
    orientation = %{yaw: 0.32, pitch: -0.17, roll: 0.08}
    [{pid, _}] = Registry.lookup(Core.World.Registry, {:world_map, first.map_id})
    :sys.replace_state(pid, fn state ->
      ship_entity = Map.fetch!(state.entities, account.id)
      updated = %{ship_entity | position: position, attitude: orientation}
      %{state | entities: Map.put(state.entities, account.id, updated)}
    end)

    assert :ok = World.disconnect(first.id)
    assert {:ok, held} = Core.Universe.Navigation.snapshot(server, account.id)
    assert held.logout_paused
    assert held.position_km == starting.position_km

    assert {:ok, second} = World.connect(account.id)
    on_exit(fn -> World.disconnect(second.id) end)
    assert second.map_id == Core.Universe.FreeFlightRegion.map_id(account.id)
    assert {:ok, restored} = World.snapshot(second.map_id)
    after_login = Enum.find(restored.entities, &(&1.id == account.id))
    assert after_login.position_3d == Map.from_struct(position)
    assert after_login.attitude == orientation
    assert after_login.ship_instance_id == ship.id
    assert {:ok, running} = Core.Universe.Navigation.snapshot(server, account.id)
    refute running.logout_paused
    assert running.position_km == held.position_km
  end

  test "real authenticated Green Starbase docking survives logout and relogin" do
    account = player_account_fixture()
    solar = Module.concat(Core.World.SessionManager, Core.Universe.Navigation)
    {:ok, _} = Core.Universe.Navigation.snapshot(solar, account.id)
    position = Core.Universe.GreenStarbase.position_km()
    :sys.replace_state(solar, fn state ->
      voyage = Map.fetch!(state.voyages, account.id)
      at_base = %{voyage |
        status: :idle, location_id: nil, origin_id: nil,
        arrival_origin_id: nil, destination_id: nil,
        position_km: position, origin_position_km: position,
        destination_position_km: nil}
      %{state | voyages: Map.put(state.voyages, account.id, at_base)}
    end)

    map_id = Core.Universe.FreeFlightRegion.map_id(account.id)
    assert {:ok, first} = World.connect(account.id)
    assert first.map_id == map_id
    # The actual ship position is owned by MapServer, not a client payload.
    [{map_pid, _}] = Registry.lookup(Core.World.Registry, {:world_map, map_id})
    site = Core.Universe.GreenStarbase.local_site()
    :sys.replace_state(map_pid, fn state ->
      ship = Map.fetch!(state.entities, account.id)
      stopped = %{ship |
        position: %Core.World.Position{x: site.x, y: site.y - 100.0, z: site.z},
        throttle: 0.0, cruise_speed: 0.0,
        destination: nil, route_waypoints: [], navigation_mode: :manual}
      %{state | entities: Map.put(state.entities, account.id, stopped)}
    end)

    assert {:ok, %{docked: true}} = World.dock(first.id)
    assert {:ok, inside} = World.snapshot(map_id)
    assert inside.docked_pilots == [account.id]
    refute Enum.any?(inside.entities, &(&1.id == account.id))
    assert :ok = World.disconnect(first.id)

    assert {:ok, second} = World.connect(account.id)
    assert second.map_id == map_id
    assert {:ok, returned} = World.snapshot(map_id)
    assert returned.docked_pilots == [account.id]
    refute Enum.any?(returned.entities, &(&1.id == account.id))
    assert {:error, :ship_docked} = World.solar_set_course(second.id, "venus")

    assert {:ok, %{docked: false, entity: ship}} = World.launch(second.id)
    assert ship.hull > 0
    assert {:ok, after_launch} = World.snapshot(map_id)
    assert after_launch.docked_pilots == []
    assert Enum.any?(after_launch.entities, &(&1.id == account.id))
    assert :ok = World.disconnect(second.id)
  end

  test "rejects a second live session for the same player" do
    account = player_account_fixture()
    assert {:ok, session} = World.connect(account.id)

    on_exit(fn -> World.disconnect(session.id) end)

    assert {:error, :already_connected} = World.connect(account.id)
  end

  test "reconnecting loads the same physical ship with its previous combat damage" do
    account = player_account_fixture()
    {:ok, owned_ship} = Darkorbit.Fleet.get_active_ship(account.id)
    assert {:ok, session} = World.connect(account.id)

    [{map_server, _}] = Registry.lookup(Core.World.Registry, {:world_map, "1-1"})
    {initial_hull, initial_shields} =
      :sys.get_state(map_server).entities
      |> Map.fetch!(account.id)
      |> then(fn entity -> {entity.hull, entity.shields} end)

    :sys.replace_state(map_server, fn state ->
      ship = Map.fetch!(state.entities, account.id)
      damaged = %{ship | hull: initial_hull - 1, shields: 0}
      %{state | entities: Map.put(state.entities, account.id, damaged)}
    end)

    assert :ok = World.disconnect(session.id)
    assert {:ok, replacement} = World.connect(account.id)
    on_exit(fn -> World.disconnect(replacement.id) end)

    {:ok, snapshot} = World.snapshot()
    rejoined = Enum.find(snapshot.entities, &(&1.id == account.id and &1.kind == :player))
    assert rejoined.ship_instance_id == owned_ship.id
    assert rejoined.hull == initial_hull - 1
    assert rejoined.shields == 0
    assert rejoined.max_shields >= initial_shields
  end

  test "a destroyed physical hull cannot reconnect fully repaired" do
    account = player_account_fixture()
    {:ok, ship} = Darkorbit.Fleet.get_active_ship(account.id)
    {:ok, stats} = Darkorbit.ShipStats.calculate(account.id, ship.id, 1)
    {:ok, condition} = Darkorbit.ShipCondition.load_or_initialize(account.id, ship.id, stats)
    assert :ok = Darkorbit.ShipCondition.save_verified(account.id, ship.id,
      %{condition | hull: 0, shields: 0, status: :destroyed})

    assert {:ok, session} = World.connect(account.id)
    on_exit(fn -> World.disconnect(session.id) end)

    {:ok, snapshot} = World.snapshot()
    ship_entity = Enum.find(snapshot.entities, &(&1.id == account.id and &1.kind == :player))
    assert ship_entity.ship_instance_id == ship.id
    assert ship_entity.status == :destroyed
    assert ship_entity.hull == 0
    assert {:error, :attacker_destroyed} = World.attack(session.id)
  end



  test "an interrupted prepared departure is recovered on the next authenticated connect" do
    account = player_account_fixture()
    assert {:ok, first} = World.connect(account.id)

    assert {:ok, %{player_id: player_id}} = Core.World.prepare_disconnect(first.id)
    assert player_id == account.id
    assert {:ok, true} = Core.World.pending_disconnect?(first.id)

    assert {:ok, second} = World.connect(account.id)
    on_exit(fn -> World.disconnect(second.id) end)
    assert second.id != first.id
    assert {:error, :session_not_found} = Core.World.ship_condition(first.id)
    assert {:ok, false} = Core.World.pending_disconnect?(second.id)
  end


end
