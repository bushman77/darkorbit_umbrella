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

    # QR invitations cannot be used to connect directly to Phoenix Socket.
    # Redeem first, retain the credential, then join as a read-only viewer.
    assert :error = connect(UserSocket, %{"pair_code" => code})
    assert {:ok, %{credential: credential}} = HelmetManager.redeem(code, "Galaxy S21")
    {:ok, helmet_socket} = connect(UserSocket, %{"helmet_token" => credential})
    assert {:error, %{reason: "map_not_found"}} =
      subscribe_and_join(helmet_socket, WorldChannel, "world:1-1")

    {:ok, %{mode: :standby}, viewer} =
      subscribe_and_join(helmet_socket, HelmetChannel, "helmet:viewer")

    assert {:ok, %{player_id: id}} = Helmets.authenticate(credential)
    assert id == account.id
    assert %{paired: true, connected: true, mode: :standby} =
      HelmetManager.status(account.id)

    # A second use of the invitation is forbidden; an enrolled viewer still
    # cannot subscribe as a pilot or send any world commands.
    assert {:error, :invalid_pairing} = HelmetManager.redeem(code, "another phone")

    ref = push(viewer, "flight_controls", %{"throttle" => 1.0})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "set_mode", %{"mode" => "combat"})
    assert_reply ref, :ok, %{mode: "combat"}
    assert_push "helmet_mode", %{mode: "combat"}
    assert_push "helmet_snapshot", %{player_id: ^id, map: %{entities: _}}

    # Regression: simulation broadcasts more event types than just snapshots.
    # A movement_started notification previously crashed the GenServer and
    # stranded the already-redeemed QR without a saved phone credential.
    send(viewer.channel_pid, {:movement_started, %{id: account.id}})
    send(viewer.channel_pid, {:movement_stopped, %{id: account.id}})
    ref = push(viewer, "rendering_status", %{"rendering" => false})
    assert_reply ref, :ok

    ref = push(viewer, "rendering_status", %{"rendering" => true})
    assert_reply ref, :ok
    assert %{rendering: true} = HelmetManager.status(account.id)

    # The phone owns and reports its actual calibration values.
    ref = push(viewer, "alignment_state", %{"eye_gap_px" => 8, "eye_sep_mm" => 64})
    assert_reply ref, :ok
    assert %{alignment: %{eye_gap_px: 8, eye_sep_mm: 64}} =
      HelmetManager.status(account.id)

    # Only the laptop's authenticated controller can adjust an actively
    # rendering phone. Viewer commands must remain read-only.
    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => 1})
    assert_reply ref, :ok, %{axis: "gap", direction: 1}
    assert_push "helmet_alignment_adjust", %{axis: "gap", direction: 1}

    ref = push(control, "adjust_alignment", %{"axis" => "eye_sep", "direction" => -1})
    assert_reply ref, :ok, %{axis: "eye_sep", direction: -1}
    assert_push "helmet_alignment_adjust", %{axis: "eye_sep", direction: -1}

    ref = push(viewer, "adjust_alignment", %{"axis" => "gap", "direction" => 1})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => 99})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(viewer, "alignment_state", %{"eye_gap_px" => 999, "eye_sep_mm" => 64})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "set_mode", %{"mode" => "standby"})
    assert_reply ref, :ok, %{mode: "standby"}
    assert_push "helmet_mode", %{mode: "standby"}
    assert %{mode: :standby, rendering: false} = HelmetManager.status(account.id)

    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => 1})
    assert_reply ref, :error, %{reason: "not_in_cockpit"}

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

    ref = push(control, "set_mode", %{"mode" => "combat"})
    assert_reply ref, :ok
    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => -1})
    assert_reply ref, :error, %{reason: "helmet_not_rendering"}

    ref = push(control, "open_pairing", %{})
    assert_reply ref, :ok, %{code: code}
    ref = push(control, "cancel_pairing", %{})
    assert_reply ref, :ok

    assert {:error, :invalid_pairing} = HelmetManager.redeem(code, "expired invitation")
    assert :error = connect(UserSocket, %{"pair_code" => code})

    assert %{paired: false, pairing: false} = HelmetManager.status(account.id)
    leave(control)
  end
end
