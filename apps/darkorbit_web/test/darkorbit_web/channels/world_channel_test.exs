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
    :ok = Core.World.clear_encounters()
    on_exit(fn ->
      clear_world()
      :ok = Core.World.clear_encounters()
    end)
    # Only tagged combat tests request a server-owned fixture encounter.
    if Map.get(tags, :encounter) do
      assert {:ok, _npc} = Core.World.start_encounter("dart")
    end
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

  test "runtime configuration starts all planetary maps, not only legacy Sector 1-1" do
    expected = %{
      "1-1" => "earth", # isolated legacy combat test fixture
      "sol:earth" => "earth",
      "sol:mercury" => "mercury",
      "sol:venus" => "venus",
      "sol:mars" => "mars",
      "sol:jupiter" => "jupiter",
      "sol:saturn" => "saturn",
      "sol:uranus" => "uranus",
      "sol:neptune" => "neptune",
      "sol:pluto" => "pluto"
    }

    for {map_id, planet_id} <- expected do
      assert {:ok, region} = World.snapshot(map_id),
             "Expected supervised region #{map_id} to be registered"
      assert region.map_id == map_id
      assert region.planet_id == planet_id
      assert is_list(region.entities)
    end
  end

  test "authenticated pilot is redirected to its actual orbital region" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)

    assert {:error, %{reason: "region_redirect", map_id: "1-1"}} =
             subscribe_and_join(socket, WorldChannel, "world:2-1")

    {:ok, response, joined_socket} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    assert response.map.map_id == "1-1"
    assert response.map.boundaries == %{width: 20_000, height: 12_000}
    assert response.player.pilot.id == account.id
    assert response.player.pilot.pilot_name == account.pilot_name
    assert response.player.stats.speed == 320
    assert response.player.stats.damage == 10
    assert response.player.ship.name == "Sunracer"
    assert response.player.stats.hit_points == 300
    assert Enum.any?(response.map.entities, &(&1.id == account.id))
    assert Enum.count(response.map.entities, &(&1.kind == :npc)) == 0
    assert response.solar_navigation.system_id == "sol"
    assert response.solar_navigation.location_id == "earth"
    assert response.solar_navigation.status == :idle
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

  test "cockpit joins with the persisted active equipment configuration" do
    account = verified_player_account_fixture()
    [owned] = Darkorbit.Fleet.list_ships_for_user(account.id)
    [_, alternate] = Darkorbit.Loadouts.list_loadouts_for_player_ship(owned.id)

    assert {:ok, _} = Darkorbit.Inventory.add_equipment(account.id, "beryl", 1)
    assert {:ok, _} =
      Darkorbit.Loadouts.equip_laser_from_inventory(
        account.id, alternate.id, "ship", 0, "beryl")
    assert {:ok, _} = Darkorbit.Accounts.activate_configuration(account.id, 2)

    {:ok, socket} = authenticated_socket(account)
    {:ok, response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    assert response.player.configuration.number == 2
    assert response.player.stats.damage == 15
    ship = Enum.find(response.map.entities, &(&1.player_id == account.id))
    assert ship.damage == 15
    leave_and_wait(joined)
  end

  test "authenticated pilot freely switches from AI cruise to deep-space cockpit and back" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(joined, "solar_enter_free_flight", %{})
    assert_reply ref, :error, %{reason: "no_active_course"}

    ref = push(joined, "solar_set_course", %{"body_id" => "mars"})
    assert_reply ref, :ok, %{navigation: %{status: :traveling, free_flight: false,
      destination_id: "mars"}}

    ref = push(joined, "solar_enter_free_flight", %{})
    assert_reply ref, :ok, %{navigation: %{free_flight: true,
      propulsion_mode: :conventional, status: :traveling}}
    map_id = Core.Universe.FreeFlightRegion.map_id(account.id)
    assert_push "world_region_changed", %{map_id: ^map_id}

    ref = push(joined, "flight_controls", %{"throttle" => 0.5})
    assert_reply ref, :error, %{reason: "wrong_flight_region"}
    leave_and_wait(joined)

    {:ok, reconnect} = authenticated_socket(account)
    {:ok, response, cockpit} =
      subscribe_and_join(reconnect, WorldChannel, "world:" <> map_id)
    assert response.map.map_id == map_id
    assert response.map.planet_id == nil # deep space has no physical planet
    assert response.solar_navigation.free_flight
    assert response.solar_navigation.status == :traveling
    assert response.solar_navigation.planetary_view == nil

    ref = push(cockpit, "flight_controls", %{"throttle" => 0.5})
    assert_reply ref, :ok, %{entity: %{kind: :player}}

    ref = push(cockpit, "solar_resume_cruise", %{})
    assert_reply ref, :ok, %{navigation: %{free_flight: false,
      propulsion_mode: :interplanetary_cruise, status: :traveling}}
    # Displaying the deep-space cockpit during cruise no longer redirects to
    # the departure planet. Only actual arrivals change orbital regions.
    refute_push "world_region_changed", %{map_id: "1-1"}
    leave_and_wait(cockpit)

    refute Core.World.MapServer.available?(Core.World.Registry, map_id)
    server = Module.concat(SessionManager, Core.Universe.Navigation)
    assert {:ok, %{free_flight: false, destination_id: "mars"}} =
      Core.Universe.Navigation.snapshot(server, account.id)
  end

  test "SOL accepts free XY game-km routes and keeps a cancelled pilot in deep space" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    {:ok, earth} = Core.Universe.Sol.game_position_km("earth")
    invalid = %{"x" => earth.x, "y" => earth.y, "z" => 0}
    ref = push(joined, "solar_set_course", %{"point" => invalid})
    assert_reply ref, :error, %{reason: "invalid_solar_waypoint"}

    point = %{"x" => earth.x + 4_000_000.0, "y" => earth.y, "z" => 0}
    ref = push(joined, "solar_set_course", %{"point" => point,
      "player_id" => -10, "origin_id" => "pluto"})
    assert_reply ref, :ok, %{navigation: %{status: :traveling,
      destination_id: nil, destination_position_km: %{x: x, y: y, z: 0.0}}}
    assert_in_delta x, point["x"], 0.01
    assert_in_delta y, point["y"], 0.01

    deep_space_id = Core.Universe.FreeFlightRegion.map_id(account.id)
    assert_push "world_region_changed", %{map_id: ^deep_space_id}
    server = Module.concat(SessionManager, Core.Universe.Navigation)
    assert :ok = Core.Universe.Navigation.tick(server)
    assert {:ok, underway} = Core.Universe.Navigation.snapshot(server, account.id)
    ref = push(joined, "solar_cancel_course", %{})
    assert_reply ref, :ok, %{navigation: %{status: :idle,
      location_id: nil, destination_id: nil}}
    leave_and_wait(joined)

    {:ok, reconnect} = authenticated_socket(account)
    {:ok, response, cockpit} =
      subscribe_and_join(reconnect, WorldChannel, "world:" <> deep_space_id)
    assert response.map.planet_id == nil
    assert response.solar_navigation.location_id == nil
    assert response.solar_navigation.position_km == underway.position_km
    leave_and_wait(cockpit)
  end

  test "arriving at Venus switches to a shared planet map with an incoming entry pose" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, old_socket} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(old_socket, "solar_set_course", %{"body_id" => "venus"})
    assert_reply ref, :ok, %{navigation: %{destination_id: "venus", status: :traveling,
      duration_ms: duration_ms}}

    server = Module.concat(SessionManager, Core.Universe.Navigation)
    # Each resolved encounter holds travel for one tick; allow additional
    # ticks for sequential traffic contacts before asserting orbital arrival.
    for _ <- 1..(ceil(duration_ms / 1_000) + 12) do
      assert :ok = Core.Universe.Navigation.tick(server)
      assert {:ok, navigation} = Core.Universe.Navigation.snapshot(server, account.id)

      if navigation.pending_encounter do
        assert {:ok, _} = Core.Universe.Navigation.resolve_encounter(
          server, account.id, navigation.pending_encounter.id, :continue)
      end
    end
    assert_push "world_region_changed", %{map_id: "sol:venus"}
    leave_and_wait(old_socket)

    {:ok, next_socket} = authenticated_socket(account)
    assert {:error, %{reason: "region_redirect", map_id: "sol:venus"}} =
      subscribe_and_join(next_socket, WorldChannel, "world:1-1")

    {:ok, venus_socket} = authenticated_socket(account)
    {:ok, response, joined} =
      subscribe_and_join(venus_socket, WorldChannel, "world:sol:venus")

    assert response.map.map_id == "sol:venus"
    assert response.map.planet_id == "venus"
    assert response.map.boundaries == %{width: 400_000, height: 400_000}
    assert response.solar_navigation.status == :idle
    assert response.solar_navigation.arrival_origin_id == "earth"
    assert response.solar_navigation.location_id == "venus"
    assert response.solar_navigation.planetary_view.body_id == "venus"
    ship = Enum.find(response.map.entities, &(&1.player_id == account.id))
    {:ok, expected} = Core.Universe.OrbitalEntry.entry(
      "earth", "venus", account.id, response.solar_navigation.voyage_number)
    assert ship.position_3d == Map.from_struct(expected.position)
    assert_in_delta ship.attitude.yaw, expected.attitude.yaw, 1.0e-9
    assert Enum.count(response.map.entities, &(&1.kind == :npc)) == 0
    leave_and_wait(joined)
  end

  test "SOL flyby event is delivered only to the authenticated pilot" do
    account = verified_player_account_fixture()
    other = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    event = %{
      player_id: account.id,
      encounter: %{
        id: "flyby:traffic:sol:vesper-02:1",
        contact_id: "traffic:sol:vesper-02",
        call_sign: "Vesper-02",
        mode: :strategic_flyby
      }
    }

    send(joined.channel_pid, {:solar_encounter_started, %{event | player_id: other.id}})
    refute_push "solar_encounter_started", _, 50

    send(joined.channel_pid, {:solar_encounter_started, event})
    assert_push "solar_encounter_started",
      %{player_id: player_id, encounter: %{contact_id: "traffic:sol:vesper-02"}}
    assert player_id == account.id
    leave_and_wait(joined)
  end


  test "a neutral procedural Harbor encounter offers a server-authorized attack" do
    account = verified_player_account_fixture()
    server = Module.concat(SessionManager, Core.Universe.Navigation)
    original_state = :sys.get_state(server)

    {:ok, traffic} =
      Core.Universe.Traffic.launch_contact(
        %{}, "earth", "venus", 1, :independent_trader, 0.5)

    :sys.replace_state(server, fn state ->
      %{state | traffic: traffic, encountered: %{},
        procedural_contact_chance: 0.0,
        voyages: Map.delete(state.voyages, account.id)}
    end)
    on_exit(fn -> :sys.replace_state(server, fn _ -> original_state end) end)

    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(joined, "solar_set_course", %{"body_id" => "venus"})
    assert_reply ref, :ok, %{navigation: %{status: :traveling}}

    held =
      Enum.reduce_while(1..125, nil, fn _, _ ->
        assert :ok = Core.Universe.Navigation.tick(server)
        {:ok, navigation} = Core.Universe.Navigation.snapshot(server, account.id)
        if navigation.pending_encounter,
          do: {:halt, navigation},
          else: {:cont, nil}
      end)

    assert %{pending_encounter: %{id: encounter_id,
                                 contact_id: "traffic:sol:cruise-1",
                                 classification: :neutral_flyby}} = held
    assert held.cruise_paused

    ref = push(joined, "solar_enter_encounter",
      %{"encounter_id" => "forged-neutral-attack"})
    assert_reply ref, :error, %{reason: "encounter_mismatch"}

    ref = push(joined, "solar_enter_encounter", %{"encounter_id" => encounter_id})
    assert_reply ref, :ok, %{navigation: %{tactical_encounter: %{
      id: ^encounter_id, classification: :neutral_flyby,
      ship_class: "scow"}}, enemy: %{kind: :npc, id: npc_id,
                                    npc_type_id: npc_type_id}}
    assert String.starts_with?(npc_type_id, "solar-scow-")
    assert {:ok, local_world} = World.snapshot("1-1")
    assert %{ship_class: "scow", npc_type_id: ^npc_type_id} =
      Enum.find(local_world.entities, &(&1.id == npc_id))

    assert {:ok, world} = World.snapshot("1-1")
    assert Enum.any?(world.entities, &(&1.id == npc_id))

    ref = push(joined, "solar_accept_surrender", %{"encounter_id" => encounter_id})
    assert_reply ref, :error, %{reason: "enemy_not_surrendered"}

    # Supplying a counterfeit manifest cannot create cargo or bypass the
    # authoritative, map-verified surrender prerequisite.
    ref = push(joined, "solar_seize_cargo",
      %{"encounter_id" => encounter_id,
        "cargo" => %{"rare_ores" => 999_999}, "faction_id" => "venus"})
    assert_reply ref, :error, %{reason: "enemy_not_surrendered"}
    assert Darkorbit.Inventory.cargo_manifest(account.id) == %{}
    assert Darkorbit.Piracy.reputations(account.id) == %{}

    assert :ok = Core.Universe.Navigation.tick(server)
    assert {:ok, paused} = Core.Universe.Navigation.snapshot(server, account.id)
    assert paused.cruise_paused

    ref = push(joined, "solar_retreat_encounter", %{"encounter_id" => encounter_id})
    assert_reply ref, :ok, %{navigation: %{
      tactical_encounter: nil, cruise_paused: false}}
    leave_and_wait(joined)
  end

  test "a hostile SOL contact enters authenticated tactical combat and can retreat" do
    account = verified_player_account_fixture()
    server = Module.concat(SessionManager, Core.Universe.Navigation)
    original_state = :sys.get_state(server)

    :sys.replace_state(server, fn state ->
      fleet = Core.Universe.Traffic.seed()
      hostile = Map.update!(fleet, "traffic:sol:vesper-02",
        &%{&1 | disposition: :hostile})
      %{state | traffic: hostile, encountered: %{},
        procedural_contact_chance: 0.0,
        voyages: Map.delete(state.voyages, account.id)}
    end)
    on_exit(fn -> :sys.replace_state(server, fn _ -> original_state end) end)

    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(joined, "solar_enter_encounter",
      %{"encounter_id" => "client-forged"})
    assert_reply ref, :error, %{reason: "no_pending_encounter"}

    ref = push(joined, "solar_set_course", %{"body_id" => "venus"})
    assert_reply ref, :ok, %{navigation: %{status: :traveling}}
    for _ <- 1..85, do: assert(:ok = Core.Universe.Navigation.tick(server))
    assert {:ok, %{pending_encounter: %{id: encounter_id},
                   cruise_paused: true}} =
      Core.Universe.Navigation.snapshot(server, account.id)

    ref = push(joined, "solar_enter_encounter", %{"encounter_id" => "forged"})
    assert_reply ref, :error, %{reason: "encounter_mismatch"}

    ref = push(joined, "solar_enter_encounter", %{"encounter_id" => encounter_id})
    assert_reply ref, :ok, %{navigation: %{tactical_encounter: %{id: ^encounter_id}},
                             enemy: %{kind: :npc, id: npc_id}}
    assert_push "npc_spawned", %{id: ^npc_id}

    ref = push(joined, "solar_resolve_encounter",
      %{"encounter_id" => encounter_id, "choice" => "continue"})
    assert_reply ref, :error, %{reason: "tactical_encounter_active"}

    ref = push(joined, "solar_retreat_encounter", %{"encounter_id" => "forged"})
    assert_reply ref, :error, %{reason: "encounter_mismatch"}

    ref = push(joined, "solar_retreat_encounter", %{"encounter_id" => encounter_id})
    assert_reply ref, :ok, %{navigation: %{tactical_encounter: nil,
      pending_encounter: nil, cruise_paused: false}}
    assert {:ok, map} = World.snapshot("1-1")
    refute Enum.any?(map.entities, &(&1.id == npc_id))
    leave_and_wait(joined)
  end

  test "encounter decision is bound to the pilot session and cannot be forged" do
    account = verified_player_account_fixture()
    server = Module.concat(SessionManager, Core.Universe.Navigation)
    original_state = :sys.get_state(server)
    # Pin the shared server's traffic schedule for this integration case;
    # unrelated channel tests may have advanced its clock already.
    :sys.replace_state(server, fn state ->
      %{state | traffic: Core.Universe.Traffic.seed(),
        encountered: %{},
        voyages: Map.delete(state.voyages, account.id)}
    end)
    on_exit(fn -> :sys.replace_state(server, fn _ -> original_state end) end)
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, socket} = subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(socket, "solar_resolve_encounter",
      %{"encounter_id" => "anything", "choice" => "continue"})
    assert_reply ref, :error, %{reason: "no_pending_encounter"}

    ref = push(socket, "solar_set_course", %{"body_id" => "venus"})
    assert_reply ref, :ok, %{navigation: %{status: :traveling}}
    for _ <- 1..85, do: assert(:ok = Core.Universe.Navigation.tick(server))
    assert {:ok, %{pending_encounter: %{id: encounter_id}, cruise_paused: true}} =
      Core.Universe.Navigation.snapshot(server, account.id)

    ref = push(socket, "solar_resolve_encounter",
      %{"encounter_id" => encounter_id, "choice" => "fight"})
    assert_reply ref, :error, %{reason: "invalid_encounter_choice"}

    ref = push(socket, "solar_cancel_course", %{})
    assert_reply ref, :error, %{reason: "encounter_decision_required"}

    ref = push(socket, "solar_resolve_encounter",
      %{"encounter_id" => "forged", "choice" => "continue"})
    assert_reply ref, :error, %{reason: "encounter_mismatch"}

    ref = push(socket, "solar_resolve_encounter",
      %{"encounter_id" => encounter_id, "choice" => "continue", "player_id" => -1})
    assert_reply ref, :ok, %{navigation: %{status: :traveling,
      cruise_paused: false, pending_encounter: nil}}

    assert {:ok, %{cruise_paused: false}} =
      Core.Universe.Navigation.snapshot(server, account.id)
    leave_and_wait(socket)
  end

  test "SOL interplanetary courses are server-authorized and no NPC spawns on travel" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, response, socket} =
      subscribe_and_join(socket, WorldChannel, "world:1-1")
    assert response.solar_navigation.location_id == "earth"

    ref = push(socket, "solar_set_course", %{"body_id" => "sun"})
    assert_reply ref, :error, %{reason: "invalid_solar_destination"}
    ref = push(socket, "solar_set_course", %{"body_id" => "mars",
      "player_id" => -1, "progress" => 1.0, "location_id" => "pluto"})
    assert_reply ref, :ok, %{navigation: %{origin_id: "earth",
      destination_id: "mars", status: :traveling}}
    assert_push "solar_navigation_updated", %{player_id: player_id,
      navigation: %{destination_id: "mars"}}
    assert player_id == account.id
    ref = push(socket, "solar_set_course", %{"body_id" => "pluto"})
    assert_reply ref, :error, %{reason: "already_traveling"}
    ref = push(socket, "flight_controls", %{"throttle" => 1.0})
    assert_reply ref, :error, %{reason: "interplanetary_cruise_active"}
    ref = push(socket, "laser_attack", %{})
    assert_reply ref, :error, %{reason: "interplanetary_cruise_active"}
    ref = push(socket, "solar_cancel_course", %{"player_id" => -1})
    assert_reply ref, :ok, %{navigation: %{location_id: "earth",
      status: :idle, destination_id: nil}}
    assert {:ok, snapshot} = World.snapshot()
    refute Enum.any?(snapshot.entities, &(&1.kind == :npc))
    leave_and_wait(socket)
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

  test "socket XYZ routes are validated and preserve authoritative altitude" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _reply, socket} = subscribe_and_join(socket, WorldChannel, "world:1-1")

    ref = push(socket, "plot_course", %{"waypoints" => [
      %{"x" => 1_000.0, "y" => 1_000.0, "z" => 96.0}
    ]})
    assert_reply ref, :ok, %{entity: %{destination_3d: %{z: 96.0}, navigation_mode: :autopilot}}

    assert {:ok, step} = World.tick()
    ship = Enum.find(step.entities, &(&1.id == account.id))
    assert ship.position_3d.z > 0.0
    assert ship.position_3d.z < 96.0
    # XY is still available for atlas projections and older map displays.
    assert ship.position == %{x: 1_000.0, y: 1_000.0}

    ref = push(socket, "plot_course", %{"waypoints" => [
      %{"x" => 1_000, "y" => 1_000, "z" => 3_001}
    ]})
    assert_reply ref, :error, %{reason: "outside_map"}

    ref = push(socket, "move", %{"x" => 1_010, "y" => 1_000, "z" => 160})
    assert_reply ref, :ok, %{entity: %{destination_3d: %{z: 160}, navigation_mode: :manual}}

    leave_and_wait(socket)
  end

  test "flight control commands cannot spoof another ship or its motion" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)
    {:ok, _response, first_socket} = subscribe_and_join(first_socket, WorldChannel, "world:1-1")
    {:ok, _response, second_socket} = subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    ref = push(first_socket, "flight_controls", %{
      "throttle" => 0.6, "yaw" => 0.0, "pitch" => 0.0,
      "roll" => 0.0, "mode" => "newtonian",
      "entity_id" => second.id, "position" => %{"x" => 20_000}
    })
    assert_reply ref, :ok, %{entity: %{id: owner_id, flight_mode: :newtonian,
                                      throttle: 0.6, angular_velocity: _rates}}
    assert owner_id == first.id

    ref = push(first_socket, "flight_controls", %{"throttle" => 100})
    assert_reply ref, :error, %{reason: "invalid_flight_controls"}

    assert {:ok, snapshot} = World.tick()
    first_ship = Enum.find(snapshot.entities, &(&1.id == first.id))
    second_ship = Enum.find(snapshot.entities, &(&1.id == second.id))
    assert first_ship.position_3d.y < 1_000.0
    assert second_ship.position_3d == %{x: 1_000.0, y: 1_000.0, z: 0.0}

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  test "Space laser ignores spoofed target, ship identity and client direction" do
    first = verified_player_account_fixture()
    second = verified_player_account_fixture()
    {:ok, first_socket} = authenticated_socket(first)
    {:ok, second_socket} = authenticated_socket(second)
    {:ok, _reply, first_socket} = subscribe_and_join(first_socket, WorldChannel, "world:1-1")
    {:ok, _reply, second_socket} = subscribe_and_join(second_socket, WorldChannel, "world:1-1")

    ref = push(first_socket, "fire_ready_weapon", %{
      "entity_id" => second.id, "session_id" => -1,
      "target_id" => "npc:1-1:made_up", "yaw" => 4.5,
      "damage" => 1_000_000
    })
    assert_reply ref, :ok, shot
    assert shot.attacker_id == first.id
    assert shot.from == %{x: 1_000.0, y: 1_000.0, z: 0.0}
    assert shot.hit in [true, false]
    assert shot.next_attack_tick > 0

    ref = push(first_socket, "fire_ready_weapon", %{})
    assert_reply ref, :error, %{reason: "weapon_cooldown"}

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

  @tag encounter: true
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
      Enum.find(first_response.map.entities, &(&1.id == "npc:1-1:dart:1"))

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

    assert_reply attack_ref, :ok, %{damage: 10, target_id: ^target_id, destroyed: false}
    assert_push "laser_fired", %{attacker_id: ^first_id, damage: 10, target_id: ^target_id}
    assert_push "laser_fired", %{attacker_id: ^first_id, damage: 10, target_id: ^target_id}

    assert {:ok, snapshot} = World.snapshot()
    damaged = Enum.find(snapshot.entities, &(&1.id == target.id))
    assert damaged.shields == target.shields - 6
    assert damaged.hull == target.hull - 4

    repeated_ref = push(first_socket, "laser_attack", %{})
    assert_reply repeated_ref, :error, %{reason: "weapon_cooldown"}

    invalid_ref = push(second_socket, "select_target", %{"target_id" => "npc:1-1:missing"})
    assert_reply invalid_ref, :error, %{reason: "target_not_found"}

    leave_and_wait(first_socket)
    leave_and_wait(second_socket)
  end

  @tag encounter: true
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

  @tag encounter: true
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

  test "delta opt-in uses sparse ticks and authenticated resync" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1", %{"stream" => "delta_v1"})

    assert response.stream == "delta_v1"

    # A genuinely changed condition must stream immediately. Empty ticks
    # are intentionally suppressed by the new adaptive policy.
    current_ship = Enum.find(response.map.entities, &(&1.player_id == account.id))
    changed_ship = %{current_ship | hull: current_ship.hull - 1}
    next_tick = response.map.tick + 1
    changed_entities =
      Enum.map(response.map.entities, fn entity ->
        if entity.id == current_ship.id, do: changed_ship, else: entity
      end)
    send(joined.channel_pid, {:world_state,
      %{response.map | tick: next_tick, entities: changed_entities}})

    assert_push "world_delta", %{base_tick: base_tick, tick: ^next_tick, entities: updates}
    assert base_tick == response.map.tick
    assert Enum.any?(updates, fn patch ->
      patch.id == current_ship.id and patch.hull == changed_ship.hull
    end)

    ref = push(joined, "world_resync", %{"map_id" => "sol:mars"})
    assert_reply ref, :ok, %{map: %{map_id: "1-1"}}
    leave_and_wait(joined)
  end

  test "unmodified channel join retains full snapshot stream" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, response, joined} = subscribe_and_join(socket, WorldChannel, "world:1-1")
    refute Map.has_key?(response, :stream)
    assert {:ok, _} = World.tick()
    assert_push "world_state", %{entities: entities}
    assert is_list(entities)
    leave_and_wait(joined)
  end

  test "delta stream suppresses unchanged frames and maintains a heartbeat" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1", %{"stream" => "delta_v1"})

    assert response.stream == "delta_v1"
    first_tick = response.map.tick

    # Exercise the replication channel with unchanged snapshots. The physics
    # integrator can legitimately normalize initial integer velocities to
    # floats, which is not part of this transport cadence regression.
    for offset <- 1..9 do
      send(joined.channel_pid,
        {:world_state, %{response.map | tick: first_tick + offset}})
    end
    refute_push "world_delta", _, 0

    expected_tick = first_tick + 10
    send(joined.channel_pid,
      {:world_state, %{response.map | tick: expected_tick}})
    assert_push "world_delta", %{base_tick: ^first_tick, tick: ^expected_tick, entities: []}
    leave_and_wait(joined)
  end

  test "delta input feedback deduplicates identical movement previews" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1", %{"stream" => "delta_v1"})

    entity = %{id: account.id, player_id: account.id, position_3d: %{x: 1, y: 2, z: 3},
      attitude: %{yaw: 0, pitch: 0, roll: 0}}

    send(joined.channel_pid, {:movement_started, entity})
    assert_push "movement_delta", %{id: _}

    send(joined.channel_pid, {:movement_started, entity})
    refute_push "movement_delta", _

    send(joined.channel_pid, {:movement_started,
      %{entity | position_3d: %{x: 2, y: 2, z: 3}}})
    assert_push "movement_delta", %{position_3d: %{x: 2}}
    leave_and_wait(joined)
  end

  test "delta stream does not duplicate NPC movement events" do
    account = verified_player_account_fixture()
    {:ok, socket} = authenticated_socket(account)
    {:ok, _response, joined} =
      subscribe_and_join(socket, WorldChannel, "world:1-1", %{"stream" => "delta_v1"})

    send(joined.channel_pid, {:npc_movement_started, %{id: "scow:1"}})
    refute_push "npc_movement_started", _
    leave_and_wait(joined)
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
