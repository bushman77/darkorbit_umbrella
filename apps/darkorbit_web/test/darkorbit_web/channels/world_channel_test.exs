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
    assert response.player.stats.damage == 40
    assert Enum.any?(response.map.entities, &(&1.id == account.id))
    assert Enum.count(response.map.entities, &(&1.kind == :npc)) == 3
    assert Enum.map(response.hotbar, & &1.key) == ~w(1 2 3 4 5 6 7 8 9 0)

    assert %{
             id: "x1_laser",
             type: :ammunition,
             activation_mode: :toggle,
             weapon_id: "pulse_emitter"
           } = Enum.at(response.hotbar, 0).action

    assert Enum.all?(Enum.drop(response.hotbar, 1), &is_nil(&1.action))

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

  test "navigation course and stop bind to authenticated player and ignore spoofed ids" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)
    {:ok, _response, first_socket} = subscribe_and_join(first_socket, WorldChannel, "world:1-1")
    {:ok, _response, second_socket} = subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    ref = push(first_socket, "plot_course", %{
      "waypoints" => [%{"x" => 1_032, "y" => 1_000}, %{"x" => 1_064, "y" => 1_000}],
      "entity_id" => second.id
    })
    assert_reply ref, :ok, %{entity: %{id: first_id, navigation_mode: :autopilot}}
    assert first_id == first.id
    assert {:ok, snapshot} = World.snapshot()
    assert Enum.find(snapshot.entities, &(&1.id == first.id)).route_waypoints == [%{x: 1_064, y: 1_000}]
    assert Enum.find(snapshot.entities, &(&1.id == second.id)).destination == nil

    ref = push(first_socket, "plot_course", %{"waypoints" => [%{"x" => 30_000, "y" => 0}]})
    assert_reply ref, :error, %{reason: "outside_map"}
    ref = push(first_socket, "stop_navigation", %{"entity_id" => second.id, "x" => 88_888})
    assert_reply ref, :ok, %{entity: %{id: ^first_id, destination: nil, route_waypoints: []}}
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

    player_ids =
      second_response.map.entities
      |> Enum.filter(&(&1.kind == :player))
      |> Enum.map(& &1.id)
      |> Enum.sort()

    assert player_ids == [first.id, second.id]
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

  test "authenticated pilots receive authoritative targeting and combat events" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)

    {:ok, first_response, first_socket} =
      subscribe_and_join(first_socket, WorldChannel, "world:1-1")

    {:ok, _second_response, second_socket} =
      subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    target =
      Enum.find(first_response.map.entities, &(&1.id == "npc:1-1:rift_skirmisher:1"))

    select_ref =
      push(first_socket, "select_target", %{
        "target_id" => target.id,
        "player_id" => second.id,
        "session_id" => -1
      })

    assert_reply select_ref, :ok, %{selection: %{player_id: first_id, target_id: target_id}}
    assert first_id == first.id
    assert target_id == target.id
    assert_push "target_selected", %{player_id: ^first_id, target_id: ^target_id}
    assert_push "target_selected", %{player_id: ^first_id, target_id: ^target_id}

    attack_ref =
      push(first_socket, "laser_attack", %{"damage" => 999_999, "target_id" => "spoof"})

    assert_reply attack_ref, :ok, %{damage: 40, target_id: ^target_id, destroyed: false}
    assert_push "laser_fired", %{attacker_id: ^first_id, damage: 40, target_id: ^target_id}
    assert_push "laser_fired", %{attacker_id: ^first_id, damage: 40, target_id: ^target_id}

    assert {:ok, snapshot} = World.snapshot()
    damaged = Enum.find(snapshot.entities, &(&1.id == target.id))
    assert damaged.shields == target.shields - 24
    assert damaged.hull == target.hull - 16

    repeated_ref = push(first_socket, "laser_attack", %{})
    assert_reply repeated_ref, :error, %{reason: "weapon_cooldown"}

    invalid_ref = push(second_socket, "select_target", %{"target_id" => "npc:1-1:missing"})
    assert_reply invalid_ref, :error, %{reason: "target_not_found"}

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  test "engagement, action activation, cancellation, and state synchronize to all pilots" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)

    {:ok, first_response, first_socket} =
      subscribe_and_join(first_socket, WorldChannel, "world:1-1")

    {:ok, _second_response, second_socket} =
      subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    target = Enum.find(first_response.map.entities, &(&1.kind == :npc))
    target_id = target.id
    first_id = first.id

    empty_ref = push(first_socket, "activate_action", %{"slot" => 2})
    assert_reply empty_ref, :ok, %{slot: 2, status: :empty, action: nil}

    invalid_ref = push(first_socket, "activate_action", %{"slot" => 0})
    assert_reply invalid_ref, :error, %{reason: "invalid_action_slot"}

    no_target_ref = push(second_socket, "engage_combat", %{})
    assert_reply no_target_ref, :error, %{reason: "no_target"}

    select_ref = push(first_socket, "select_target", %{"target_id" => target_id})
    assert_reply select_ref, :ok, %{selection: %{target_id: ^target_id}}
    assert_push "target_selected", %{player_id: ^first_id, target_id: ^target_id}
    assert_push "target_selected", %{player_id: ^first_id, target_id: ^target_id}

    action_ref = push(first_socket, "activate_action", %{"slot" => 1})

    assert_reply action_ref, :ok, %{
      slot: 1,
      status: :activated,
      engagement: %{
        player_id: ^first_id,
        target_id: ^target_id,
        active: true,
        changed: true
      }
    }

    assert_push "combat_engaged", %{player_id: ^first_id, target_id: ^target_id}
    assert_push "combat_engaged", %{player_id: ^first_id, target_id: ^target_id}

    toggle_ref = push(first_socket, "toggle_laser_fire", %{"target_id" => "spoof"})

    assert_reply toggle_ref, :ok, %{
      player_id: ^first_id,
      target_id: ^target_id,
      engaged_target_id: nil,
      active: false,
      reason: :laser_toggled_off
    }

    assert_push "combat_disengaged", %{
      player_id: ^first_id,
      previous_target_id: ^target_id,
      reason: :laser_toggled_off
    }

    assert_push "combat_disengaged", %{
      player_id: ^first_id,
      previous_target_id: ^target_id,
      reason: :laser_toggled_off
    }

    assert {:ok, stopped_snapshot} = World.snapshot()
    stopped = Enum.find(stopped_snapshot.entities, &(&1.id == first.id))
    assert stopped.target_id == target_id
    assert stopped.engaged_target_id == nil

    resume_ref = push(first_socket, "activate_action", %{"slot" => 1})

    assert_reply resume_ref, :ok, %{
      slot: 1,
      engagement: %{player_id: ^first_id, target_id: ^target_id, active: true}
    }

    assert_push "combat_engaged", %{player_id: ^first_id, target_id: ^target_id}
    assert_push "combat_engaged", %{player_id: ^first_id, target_id: ^target_id}

    repeated_ref = push(first_socket, "engage_combat", %{})
    assert_reply repeated_ref, :ok, %{target_id: ^target_id, active: true, changed: false}

    assert {:ok, %{entities: synchronized_entities}} = World.tick()
    synchronized = Enum.find(synchronized_entities, &(&1.id == first.id))
    assert synchronized.target_id == target_id
    assert synchronized.engaged_target_id == target_id

    assert_push "world_state", %{entities: first_view}
    assert_push "world_state", %{entities: second_view}
    assert Enum.find(first_view, &(&1.id == first.id)).engaged_target_id == target_id
    assert Enum.find(second_view, &(&1.id == first.id)).engaged_target_id == target_id

    cancel_ref = push(first_socket, "disengage_combat", %{})

    assert_reply cancel_ref, :ok, %{
      player_id: ^first_id,
      target_id: nil,
      previous_target_id: ^target_id,
      reason: :cancelled
    }

    assert_push "combat_disengaged", %{player_id: ^first_id, reason: :cancelled}
    assert_push "combat_disengaged", %{player_id: ^first_id, reason: :cancelled}
    assert_push "target_cleared", %{player_id: ^first_id, target_id: nil}
    assert_push "target_cleared", %{player_id: ^first_id, target_id: nil}

    assert {:ok, snapshot} = World.snapshot()
    cancelled = Enum.find(snapshot.entities, &(&1.id == first.id))
    assert cancelled.target_id == nil
    assert cancelled.engaged_target_id == nil

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  test "disconnecting during pursuit clears the authoritative NPC target" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, socket} = subscribe_and_join(socket, WorldChannel, "world:1-1")

    assert {:ok, _tick} = World.tick()
    assert {:ok, pursuing} = World.snapshot()
    assert Enum.any?(pursuing.entities, &(&1.kind == :npc and &1.target_id == account.id))

    leave_and_wait(socket)

    assert {:ok, disconnected} = World.snapshot()
    refute Enum.any?(disconnected.entities, &(&1.kind == :player and &1.id == account.id))

    assert Enum.all?(
             Enum.filter(disconnected.entities, &(&1.kind == :npc)),
             &is_nil(&1.target_id)
           )
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
        snapshot.entities
        |> Enum.filter(&(&1.kind == :player))
        |> Enum.each(fn entity ->
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
