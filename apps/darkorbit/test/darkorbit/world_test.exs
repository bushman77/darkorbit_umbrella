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
