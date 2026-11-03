defmodule DarkorbitWeb.HelmetChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest
  import Darkorbit.AccountsFixtures

  alias Darkorbit.Helmets
  alias DarkorbitWeb.{GameAuth, HelmetChannel, HelmetManager, UserSocket, WorldChannel}

  @endpoint DarkorbitWeb.Endpoint

  setup tags do
    # Phoenix.ChannelTest links joined channels to the test process. Explicit
    # leave/1 produces {:shutdown, :left}; trap it instead of killing ExUnit.
    Process.flag(:trap_exit, true)
    Darkorbit.DataCase.setup_sandbox(tags)
    :ok
  end

  test "the Atlas pairing code authorizes exactly one persistent read-only helmet" do
    account = verified_player_account_fixture()
    {:ok, pilot} = connect(UserSocket, %{"token" => GameAuth.socket_token(account)})
    {:ok, %{status: %{paired: false}, network_hosts: hosts}, control} =
      subscribe_and_join(pilot, HelmetChannel, "helmet:control:#{account.id}")
    assert is_list(hosts)
    refute Enum.any?(hosts, &(&1 in ["localhost", "127.0.0.1"]))

    ref = push(control, "open_pairing", %{})
    assert_reply ref, :ok, %{code: code}
    assert byte_size(code) == 43

    {:ok, pending} = connect(UserSocket, %{"pair_code" => code})
    assert {:error, %{reason: "map_not_found"}} =
      subscribe_and_join(pending, WorldChannel, "world:1-1")

    {:ok, %{credential: credential, mode: :standby}, viewer} =
      subscribe_and_join(pending, HelmetChannel, "helmet:viewer",
        %{"device_name" => "Galaxy S21"})

    assert {:ok, %{player_id: id}} = Helmets.authenticate(credential)
    assert id == account.id
    assert %{paired: true, connected: true, mode: :standby} =
      HelmetManager.status(account.id)

    # A second use of the invitation is forbidden; an enrolled viewer still
    # cannot subscribe as a pilot or send any world commands.
    {:ok, replay} = connect(UserSocket, %{"pair_code" => code})
    assert {:error, %{reason: "invalid_pairing"}} =
      subscribe_and_join(replay, HelmetChannel, "helmet:viewer",
        %{"device_name" => "another phone"})

    ref = push(viewer, "flight_controls", %{"throttle" => 1.0})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "set_mode", %{"mode" => "combat"})
    assert_reply ref, :ok, %{mode: "combat"}
    assert_push "helmet_mode", %{mode: "combat"}
    assert_push "helmet_snapshot", %{player_id: ^id, map: %{entities: _}}

    ref = push(viewer, "rendering_status", %{"rendering" => true})
    assert_reply ref, :ok
    assert %{rendering: true} = HelmetManager.status(account.id)

    ref = push(control, "set_mode", %{"mode" => "standby"})
    assert_reply ref, :ok, %{mode: "standby"}
    assert_push "helmet_mode", %{mode: "standby"}
    assert %{mode: :standby, rendering: false} = HelmetManager.status(account.id)

    leave(viewer)
    assert {:ok, _device} = Helmets.authenticate(credential)

    # The remembered credential is valid after the first WebSocket leaves.
    {:ok, remembered} = connect(UserSocket, %{"helmet_token" => credential})
    assert {:error, %{reason: "map_not_found"}} =
      subscribe_and_join(remembered, WorldChannel, "world:1-1")
    {:ok, _, again} = subscribe_and_join(remembered, HelmetChannel, "helmet:viewer")

    ref = push(control, "forget", %{})
    assert_reply ref, :ok
    assert :error = Helmets.authenticate(credential)
    assert %{paired: false} = HelmetManager.status(account.id)

    # Revocation stops the viewer channel; do not send a leave to a dead PID.
    leave(control)
  end

  test "opening and closing the Atlas pairing panel controls invitation lifetime" do
    account = verified_player_account_fixture()
    {:ok, pilot} = connect(UserSocket, %{"token" => GameAuth.socket_token(account)})
    {:ok, _, control} =
      subscribe_and_join(pilot, HelmetChannel, "helmet:control:#{account.id}")

    ref = push(control, "open_pairing", %{})
    assert_reply ref, :ok, %{code: code}
    ref = push(control, "cancel_pairing", %{})
    assert_reply ref, :ok

    {:ok, pending} = connect(UserSocket, %{"pair_code" => code})
    assert {:error, %{reason: "invalid_pairing"}} =
      subscribe_and_join(pending, HelmetChannel, "helmet:viewer",
        %{"device_name" => "expired invitation"})

    assert %{paired: false, pairing: false} = HelmetManager.status(account.id)
    leave(control)
  end
end
