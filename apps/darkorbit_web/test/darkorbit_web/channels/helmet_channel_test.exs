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

  test "standalone pilot control advertises opt-in secure phone pairing address" do
    account = verified_player_account_fixture()
    old = Application.get_env(:darkorbit_web, :helmet_dev_lan_https_origin)
    on_exit(fn ->
      if is_nil(old) do
        Application.delete_env(:darkorbit_web, :helmet_dev_lan_https_origin)
      else
        Application.put_env(:darkorbit_web, :helmet_dev_lan_https_origin, old)
      end
    end)
    Application.put_env(:darkorbit_web, :helmet_dev_lan_https_origin,
      "https://192.168.0.48:4443")

    {:ok, pilot} = connect(UserSocket, %{"token" => GameAuth.socket_token(account)})
    assert {:ok, %{helmet_https_origin: "https://192.168.0.48:4443"},
            control} =
      subscribe_and_join(pilot, HelmetChannel, "helmet:control:#{account.id}")
    leave(control)
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

    {:ok, %{mode: :standby, calibration: nil}, viewer} =
      subscribe_and_join(helmet_socket, HelmetChannel, "helmet:viewer")

    assert {:ok, %{player_id: id, id: device_id}} = Helmets.authenticate(credential)
    assert id == account.id
    assert %{paired: true, connected: true, mode: :standby} =
      HelmetManager.status(account.id)

    # A second use of the invitation is forbidden; an enrolled viewer still
    # cannot subscribe as a pilot or send any world commands.
    assert {:error, :invalid_pairing} = HelmetManager.redeem(code, "another phone")

    ref = push(viewer, "flight_controls", %{"throttle" => 1.0})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    # The paired headset can display an intercept but cannot enter, finish
    # or otherwise control the authoritative combat/flight session.
    ref = push(viewer, "solar_enter_encounter", %{"encounter_id" => "forged"})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}
    ref = push(viewer, "solar_retreat_encounter", %{"encounter_id" => "forged"})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}
    ref = push(viewer, "solar_accept_surrender", %{"encounter_id" => "forged"})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "set_mode", %{"mode" => "combat"})
    assert_reply ref, :ok, %{mode: "combat"}
    assert_push "helmet_mode", %{mode: "combat"}
    assert_push "helmet_snapshot", %{player_id: ^id, map: %{entities: _}}
    # A paired viewer must get the planet preview from the pilot's own
    # SOL navigation snapshot, or Three.js cannot draw planetary bodies.
    assert_push "helmet_navigation",
      %{planetary_view: %{body_id: "earth", stage: :orbital_preview}}

    # A real encounter hold is mirrored only to the paired pilot's HMD.
    # The viewer receives a read-only alert, not cargo or a flight command.
    encounter_id = "flyby:traffic:sol:vesper-02:1"
    encounter = %{
      id: encounter_id, call_sign: "Vesper-02", classification: :neutral_flyby,
      kind: :courier, distance_km: 120_000.0, cargo: %{secret: 999}
    }

    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_encounter_started, %{player_id: id, encounter: encounter}})

    assert_push "helmet_encounter", %{paused: true, encounter: %{id: ^encounter_id,
      call_sign: "Vesper-02", classification: :neutral_flyby} = visual}
    refute Map.has_key?(visual, :cargo)

    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_encounter_started, %{player_id: id + 1,
                                   encounter: %{id: "foreign-encounter"}}})
    refute_push "helmet_encounter", %{encounter: %{id: "foreign-encounter"}}, 30

    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_navigation_updated, %{player_id: id,
                                    navigation: %{pending_encounter: nil}}})
    assert_push "helmet_encounter", %{paused: false, encounter: nil}
    assert_push "helmet_navigation", %{planetary_view: nil}

    # Only presentation metadata from the paired pilot may reach the HMD.
    visual = %{body_id: "venus", stage: :approach_preview,
      visual_only: true, angular_diameter_deg: 4.0,
      radius_km: 6051.8, visual_distance_km:
        6051.8 / :math.sin(4.0 * :math.pi() / 360)}
    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_navigation_updated, %{player_id: id,
        navigation: %{planetary_view: visual, pending_encounter: nil,
          cargo: %{secret: 1}}}})
    assert_push "helmet_navigation", %{planetary_view: ^visual}
    assert_push "helmet_encounter", %{paused: false, encounter: nil}

    # A confirmed Green Starbase approach delivers only canonical, read-only
    # render metadata: the headset never receives cargo or client locations.
    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_navigation_updated, %{player_id: id,
        navigation: %{status: :idle, location_id: nil,
          green_starbase_nearby: true, planetary_view: nil,
          cargo: %{secret: 500}, pending_encounter: nil}}})
    assert_push "helmet_navigation", %{status: :idle, location_id: nil,
      green_starbase_nearby: true, starbases: [base]} = station_visual
    assert base.id == "sol:starbase:green"
    assert base.model == :green_pyramid_starbase_v1
    assert base.site_3d == Core.Universe.GreenStarbase.local_site()
    refute Map.has_key?(station_visual, :cargo)
    assert_push "helmet_encounter", %{paused: false, encounter: nil}

    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_navigation_updated, %{player_id: id,
        navigation: %{status: :traveling, location_id: nil,
          green_starbase_nearby: false, planetary_view: nil,
          pending_encounter: nil}}})
    assert_push "helmet_navigation", navigation_without_base
    refute Map.has_key?(navigation_without_base, :starbases)
    assert_push "helmet_encounter", %{paused: false, encounter: nil}

    Phoenix.PubSub.broadcast(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"),
      {:solar_navigation_updated, %{player_id: id + 1,
        navigation: %{planetary_view: %{body_id: "mars"}, pending_encounter: nil}}})
    refute_push "helmet_navigation", %{planetary_view: %{body_id: "mars"}}, 30

    ref = push(viewer, "solar_resolve_encounter",
      %{"encounter_id" => encounter_id, "choice" => "continue"})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

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

    # Centering is an authenticated display-only command. It does not
    # let the phone steer or affect another pilot's viewer.
    ref = push(control, "recenter", %{})
    assert_reply ref, :ok
    assert_push "helmet_recenter", %{}

    ref = push(viewer, "recenter", %{})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(viewer, "adjust_alignment", %{"axis" => "gap", "direction" => 1})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => 99})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    # Negative alignment is a legal inward shift and remains phone-owned.
    ref = push(viewer, "alignment_state", %{"eye_gap_px" => -60, "eye_sep_mm" => 64})
    assert_reply ref, :ok
    assert %{alignment: %{eye_gap_px: -60}} = HelmetManager.status(account.id)

    # Status messages are not writes; the phone saves a debounced snapshot.
    assert nil == Helmets.calibration(device_id)
    ref = push(viewer, "save_alignment", %{"eye_gap_px" => -60, "eye_sep_mm" => 64})
    assert_reply ref, :ok, %{eye_gap_px: -60, eye_sep_mm: 64}
    assert %{eye_gap_px: -60, eye_sep_mm: 64} = Helmets.calibration(device_id)

    # A pilot/controller cannot spoof phone settings, and bad device values
    # never enter the database.
    ref = push(control, "save_alignment", %{"eye_gap_px" => 22, "eye_sep_mm" => 72})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}
    ref = push(viewer, "save_alignment", %{"eye_gap_px" => -161, "eye_sep_mm" => 64})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}
    assert %{eye_gap_px: -60, eye_sep_mm: 64} = Helmets.calibration(device_id)

    ref = push(viewer, "alignment_state", %{"eye_gap_px" => -161, "eye_sep_mm" => 64})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(viewer, "alignment_state", %{"eye_gap_px" => 999, "eye_sep_mm" => 64})
    assert_reply ref, :error, %{reason: "read_only_or_invalid_command"}

    ref = push(control, "set_mode", %{"mode" => "standby"})
    assert_reply ref, :ok, %{mode: "standby"}
    assert_push "helmet_mode", %{mode: "standby"}
    assert %{mode: :standby, rendering: false} = HelmetManager.status(account.id)

    ref = push(control, "adjust_alignment", %{"axis" => "gap", "direction" => 1})
    assert_reply ref, :error, %{reason: "not_in_cockpit"}
    ref = push(control, "recenter", %{})
    assert_reply ref, :error, %{reason: "not_in_cockpit"}

    # ChannelTest leave is asynchronous. Observe termination before the
    # sandbox owner exits, so the global HelmetManager cannot do a delayed
    # database-backed status notification after the transaction closes.
    first_viewer_pid = viewer.channel_pid
    first_viewer_monitor = Process.monitor(first_viewer_pid)
    leave(viewer)
    assert_receive {:DOWN, ^first_viewer_monitor, :process, ^first_viewer_pid, _}, 1_000
    assert {:ok, _device} = Helmets.authenticate(credential)

    # The remembered credential is valid after the first WebSocket leaves.
    {:ok, remembered} = connect(UserSocket, %{"helmet_token" => credential})
    assert {:error, %{reason: "map_not_found"}} =
      subscribe_and_join(remembered, WorldChannel, "world:1-1")
    {:ok, %{calibration: restored}, again} =
      subscribe_and_join(remembered, HelmetChannel, "helmet:viewer")
    assert restored == %{eye_gap_px: -60, eye_sep_mm: 64}

    remembered_pid = again.channel_pid
    remembered_monitor = Process.monitor(remembered_pid)
    ref = push(control, "forget", %{})
    assert_reply ref, :ok
    assert_push "helmet_revoked", %{}
    assert_receive {:DOWN, ^remembered_monitor, :process, ^remembered_pid, _}, 1_000
    assert :error = Helmets.authenticate(credential)
    assert %{paired: false} = HelmetManager.status(account.id)

    # Wait for controller terminate callbacks, which query device status
    # through HelmetManager, before the SQL sandbox is released.
    control_pid = control.channel_pid
    control_monitor = Process.monitor(control_pid)
    leave(control)
    assert_receive {:DOWN, ^control_monitor, :process, ^control_pid, _}, 1_000
    assert %{paired: false, connected: false} = HelmetManager.status(account.id)
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
    ref = push(control, "recenter", %{})
    assert_reply ref, :error, %{reason: "helmet_not_rendering"}

    ref = push(control, "open_pairing", %{})
    assert_reply ref, :ok, %{code: code}
    ref = push(control, "cancel_pairing", %{})
    assert_reply ref, :ok

    assert {:error, :invalid_pairing} = HelmetManager.redeem(code, "expired invitation")
    assert :error = connect(UserSocket, %{"pair_code" => code})

    assert %{paired: false, pairing: false} = HelmetManager.status(account.id)
    control_pid = control.channel_pid
    control_monitor = Process.monitor(control_pid)
    leave(control)
    assert_receive {:DOWN, ^control_monitor, :process, ^control_pid, _}, 1_000
  end
end
