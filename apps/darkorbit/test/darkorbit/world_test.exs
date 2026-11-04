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


end
