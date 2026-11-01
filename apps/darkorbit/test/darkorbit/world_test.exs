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
    assert [%{position: %{x: first_x}}] = first_tick.entities
    assert_in_delta first_x, 1_032.0, 0.000_001
    assert_receive {:world_state, %{tick: ^first_tick_number}}

    second_tick_number = first_tick_number + 1
    assert {:ok, second_tick} = World.tick()
    assert [%{position: %{x: 1_064.0, y: 1_000.0}, destination: nil}] = second_tick.entities
    assert_receive {:world_state, %{tick: ^second_tick_number}}
  end

  test "rejects a second live session for the same player" do
    account = player_account_fixture()
    assert {:ok, session} = World.connect(account.id)

    on_exit(fn -> World.disconnect(session.id) end)

    assert {:error, :already_connected} = World.connect(account.id)
  end
end
