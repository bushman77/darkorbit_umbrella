defmodule DarkorbitWeb.WorldChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  import Darkorbit.AccountsFixtures

  alias Core.World.SessionManager
  alias Darkorbit.World
  alias DarkorbitWeb.GameAuth
  alias DarkorbitWeb.UserSocket
  alias DarkorbitWeb.WorldChannel

  @endpoint DarkorbitWeb.Endpoint

  setup tags do
    Process.flag(:trap_exit, true)
    Darkorbit.DataCase.setup_sandbox(tags)
    clear_world()
    on_exit(&clear_world/0)
    :ok
  end

  test "socket authentication rejects missing, tampered, and stale credentials" do
    account = verified_player_account_fixture()
    token = GameAuth.socket_token(account)

    assert :error = connect(UserSocket, %{})
    assert :error = connect(UserSocket, %{"token" => token <> "tampered"})

    assert {:ok, _account} = Darkorbit.Accounts.logout_account(account.id, account.session_id)
    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "authenticated pilot joins only map 1-1 and receives authoritative state" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)

    assert {:error, %{reason: "map_not_found"}} =
             subscribe_and_join(socket, WorldChannel, "world:2-1")

    {:ok, response, joined_socket} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    assert response.map.map_id == "1-1"
    assert response.map.boundaries == %{width: 20_000, height: 12_000}
    assert response.player.pilot.id == account.id
    assert response.player.pilot.pilot_name == account.pilot_name
    assert response.player.stats.speed == 320
    assert Enum.any?(response.map.entities, &(&1.id == account.id))

    leave_and_wait(joined_socket)
  end

  test "movement commands are authorized to the channel session and validated by Core.World" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)
    {:ok, _response, first_socket} = subscribe_and_join(first_socket, WorldChannel, "world:1-1")
    {:ok, _response, second_socket} = subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    ref =
      push(first_socket, "move", %{
        "x" => 1_064.0,
        "y" => 1_000.0,
        "entity_id" => second.id,
        "session_id" => -1
      })

    assert_reply ref, :ok, %{entity: %{id: first_id, destination: %{x: 1_064.0}}}
    assert first_id == first.id

    assert {:ok, snapshot} = World.snapshot()
    first_entity = Enum.find(snapshot.entities, &(&1.id == first.id))
    second_entity = Enum.find(snapshot.entities, &(&1.id == second.id))
    assert first_entity.destination == %{x: 1_064.0, y: 1_000.0}
    assert second_entity.destination == nil

    ref = push(first_socket, "move", %{"x" => 20_001, "y" => 1_000})
    assert_reply ref, :error, %{reason: "outside_map"}

    ref = push(first_socket, "move", %{"x" => "not-a-coordinate", "y" => 1_000})
    assert_reply ref, :error, %{reason: "invalid_destination"}

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  test "map subscribers receive tick events from the authoritative simulation" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, response, socket} = subscribe_and_join(socket, WorldChannel, "world:1-1")

    next_tick = response.map.tick + 1
    assert {:ok, %{tick: ^next_tick}} = World.tick()
    assert_push "world_state", %{tick: ^next_tick, entities: entities}
    assert Enum.any?(entities, &(&1.id == account.id))

    leave_and_wait(socket)
  end

  test "leaving the channel disconnects the Core session and removes the entity" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, socket} = subscribe_and_join(socket, WorldChannel, "world:1-1")
    channel_pid = socket.channel_pid
    monitor_ref = Process.monitor(channel_pid)

    leave_ref = leave(socket)
    assert_reply leave_ref, :ok
    assert_receive {:DOWN, ^monitor_ref, :process, ^channel_pid, reason}
    assert reason in [:normal, {:shutdown, :left}]

    assert :error = SessionManager.fetch_player(SessionManager, account.id)
    assert {:ok, snapshot} = World.snapshot()
    refute Enum.any?(snapshot.entities, &(&1.id == account.id))
  end

  test "simultaneous pilots see the same players and authoritative movement" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)

    {:ok, _first_response, first_socket} =
      subscribe_and_join(first_socket, WorldChannel, "world:1-1")

    {:ok, second_response, second_socket} =
      subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    assert second_response.pilots |> Map.keys() |> Enum.sort() == [first.id, second.id]
    assert Enum.sort(Enum.map(second_response.map.entities, & &1.id)) == [first.id, second.id]
    second_id = second.id
    assert_push "entity_joined", %{id: ^second_id, pilot: %{pilot_name: second_name}}
    assert second_name == second.pilot_name

    move_ref = push(first_socket, "move", %{"x" => 1_032.0, "y" => 1_000.0})
    assert_reply move_ref, :ok, %{entity: %{id: first_id}}
    assert first_id == first.id
    assert {:ok, %{entities: entities}} = World.tick()

    moved = Enum.find(entities, &(&1.id == first.id))
    stationary = Enum.find(entities, &(&1.id == second.id))
    assert moved.position == %{x: 1_032.0, y: 1_000.0}
    assert stationary.position == %{x: 1_000.0, y: 1_000.0}
    assert_push "world_state", %{entities: first_view}
    assert_push "world_state", %{entities: second_view}
    assert Enum.map(first_view, & &1.position) == Enum.map(second_view, & &1.position)

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  defp authenticated_socket(account) do
    connect(UserSocket, %{"token" => GameAuth.socket_token(account)})
  end

  defp leave_and_wait(socket) do
    channel_pid = socket.channel_pid
    monitor_ref = Process.monitor(channel_pid)
    leave_ref = leave(socket)
    assert_reply leave_ref, :ok
    assert_receive {:DOWN, ^monitor_ref, :process, ^channel_pid, reason}
    assert reason in [:normal, {:shutdown, :left}]
  end

  defp clear_world do
    case World.snapshot() do
      {:ok, snapshot} ->
        Enum.each(snapshot.entities, fn entity ->
          case SessionManager.fetch_player(SessionManager, entity.player_id) do
            {:ok, session} -> World.disconnect(session.id)
            :error -> :ok
          end
        end)

      {:error, _reason} ->
        :ok
    end
  end
end
