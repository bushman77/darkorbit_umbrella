defmodule DarkorbitWeb.WorldChannel do
  use DarkorbitWeb, :channel

  alias Darkorbit.World

  alias DarkorbitWeb.{WorldStreamDelta, WorldStreamPolicy}

  @impl true
  def join("world:" <> map_id, payload,
           %{assigns: %{socket_role: :pilot}} = socket) do
    player_id = socket.assigns.current_player_id
    configuration = World.active_configuration(player_id)

    with {:ok, region} <- World.region_for_player(player_id) do
      if region.map_id != map_id do
        {:error, %{reason: "region_redirect", map_id: region.map_id}}
      else
        with :ok <- World.subscribe(map_id),
             :ok <- World.subscribe("sol"),
             {:ok, status} <- World.player_status(player_id, configuration),
             {:ok, session} <- World.connect(player_id, configuration, map_id: map_id) do
          finish_join(socket, map_id, session, status, payload)
        else
          {:error, reason} -> {:error, %{reason: error_reason(reason)}}
        end
      end
    else
      {:error, reason} -> {:error, %{reason: error_reason(reason)}}
    end
  end

  def join("world:" <> _map_id, _payload, _socket) do
    {:error, %{reason: "map_not_found"}}
  end

  @impl true
  def handle_in("move", %{"x" => x, "y" => y, "z" => z}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    case World.move(socket.assigns.world_session_id, %{x: x, y: y, z: z}) do
      {:ok, entity} -> {:reply, {:ok, %{entity: entity}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("move", %{"x" => x, "y" => y}, socket)
      when is_number(x) and is_number(y) do
    case World.move(socket.assigns.world_session_id, %{x: x, y: y}) do
      {:ok, entity} -> {:reply, {:ok, %{entity: entity}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("move", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_destination"}}, socket}
  end

  def handle_in("plot_course", %{"waypoints" => waypoints}, socket) do
    case World.plot_course(socket.assigns.world_session_id, waypoints) do
      {:ok, entity} -> {:reply, {:ok, %{entity: entity}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("plot_course", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_course"}}, socket}
  end

  def handle_in("solar_set_course", %{"body_id" => body_id}, socket)
      when is_binary(body_id) do
    case World.solar_set_course(socket.assigns.world_session_id, body_id) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_set_course", %{"point" => point}, socket) when is_map(point) do
    case World.solar_set_course(socket.assigns.world_session_id, point) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_set_course", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_solar_destination"}}, socket}

  def handle_in("solar_enter_free_flight", _payload, socket) do
    case World.solar_enter_free_flight(socket.assigns.world_session_id) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_resume_cruise", _payload, socket) do
    case World.solar_resume_cruise(socket.assigns.world_session_id) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_cancel_course", _payload, socket) do
    case World.solar_cancel_course(socket.assigns.world_session_id) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_resolve_encounter",
        %{"encounter_id" => id, "choice" => "continue"}, socket)
      when is_binary(id) do
    case World.solar_resolve_encounter(socket.assigns.world_session_id, id, :continue) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_resolve_encounter", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_encounter_choice"}}, socket}

  def handle_in("solar_enter_encounter", %{"encounter_id" => id}, socket)
      when is_binary(id) do
    case World.solar_enter_tactical(socket.assigns.world_session_id, id) do
      {:ok, result} -> {:reply, {:ok, result}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_enter_encounter", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_encounter"}}, socket}

  def handle_in("solar_retreat_encounter", %{"encounter_id" => id}, socket)
      when is_binary(id) do
    case World.solar_finish_tactical(socket.assigns.world_session_id, id, :retreat) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_retreat_encounter", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_encounter"}}, socket}

  def handle_in("solar_accept_surrender", %{"encounter_id" => id}, socket)
      when is_binary(id) do
    case World.solar_finish_tactical(socket.assigns.world_session_id, id, :surrender) do
      {:ok, navigation} -> {:reply, {:ok, %{navigation: navigation}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_accept_surrender", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_encounter"}}, socket}

  # A distinct deliberate piracy choice: verified surrender is mandatory,
  # the player never supplies an item, quantity, faction, or target ship.
  def handle_in("solar_seize_cargo", %{"encounter_id" => id}, socket)
      when is_binary(id) do
    case World.solar_finish_tactical(socket.assigns.world_session_id, id,
           :surrender, claim_cargo: true) do
      {:ok, navigation} ->
        receipt = World.cargo_claim_receipt(socket.assigns.current_player_id, id)
        case receipt do
          {:ok, cargo} -> {:reply, {:ok, %{navigation: navigation, claim: cargo}}, socket}
          {:error, reason} ->
            {:reply, {:error, %{reason: error_reason(reason)}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_seize_cargo", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_encounter"}}, socket}

  def handle_in("solar_hail", %{"contact_id" => id}, socket)
      when is_binary(id) do
    case World.solar_hail(socket.assigns.world_session_id, id) do
      {:ok, communication} -> {:reply, {:ok, %{communication: communication}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("solar_hail", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_contact"}}, socket}

  def handle_in("stop_navigation", _payload, socket) do
    case World.stop_navigation(socket.assigns.world_session_id) do
      {:ok, entity} -> {:reply, {:ok, %{entity: entity}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("flight_controls", input, socket) when is_map(input) do
    # No full entity acknowledgement on opt-in delta streams. The immediate
    # movement_delta event and the next authoritative tick convey its state.
    case World.flight_controls(socket.assigns.world_session_id, input) do
      {:ok, entity} ->
        payload = if socket.assigns[:world_stream] == :delta_v1,
          do: %{accepted: true}, else: %{entity: entity}
        {:reply, {:ok, payload}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("select_target", %{"target_id" => target_id}, socket)
      when is_binary(target_id) do
    case World.select_target(socket.assigns.world_session_id, target_id) do
      {:ok, selection} -> {:reply, {:ok, selection}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("select_target", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_target"}}, socket}
  end

  def handle_in("clear_target", _payload, socket) do
    case World.clear_target(socket.assigns.world_session_id) do
      {:ok, selection} -> {:reply, {:ok, selection}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("engage_combat", _payload, socket) do
    case World.engage_combat(socket.assigns.world_session_id) do
      {:ok, engagement} -> {:reply, {:ok, engagement}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("disengage_combat", _payload, socket) do
    case World.disengage_combat(socket.assigns.world_session_id) do
      {:ok, engagement} -> {:reply, {:ok, engagement}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("toggle_laser_fire", _payload, socket) do
    case World.toggle_laser_fire(socket.assigns.world_session_id) do
      {:ok, engagement} -> {:reply, {:ok, engagement}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("activate_action", %{"slot" => slot}, socket) when is_integer(slot) do
    case World.activate_action(socket.assigns.world_session_id, slot) do
      {:ok, activation} -> {:reply, {:ok, activation}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("activate_action", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_action_slot"}}, socket}
  end

  def handle_in("fire_ready_weapon", _payload, socket) do
    # Ship identity, heading and cooldown all come from the channel session.
    case World.fire_ready_weapon(socket.assigns.world_session_id) do
      {:ok, shot} -> {:reply, {:ok, shot}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  def handle_in("laser_attack", _payload, socket) do
    case World.attack(socket.assigns.world_session_id) do
      {:ok, attack} -> {:reply, {:ok, attack}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  # A client may request resynchronization only for its authenticated map.
  def handle_in("world_resync", _payload,
                %{assigns: %{world_stream: :delta_v1, map_id: map_id}} = socket) do
    case World.snapshot(map_id) do
      {:ok, map} ->
        {:reply, {:ok, %{map: map}},
         socket |> assign(:world_baseline, map) |> assign(:movement_previews, %{})}
      {:error, reason} -> {:reply, {:error, %{reason: error_reason(reason)}}, socket}
    end
  end

  @impl true
  def handle_info({:world_state, %{tick: tick} = map},
                  %{assigns: %{world_stream: :delta_v1, world_baseline: %{tick: base} = old}} = socket) do
    if tick > base do
      # Apply per-pilot spatial relevance ONLY to visual motion. The owned ship,
      # nearby ships, damage and tactical state always replicate immediately.
      projected = WorldStreamPolicy.project(map, old, socket.assigns.current_player_id)
      delta = WorldStreamDelta.between(old, projected)

      if WorldStreamPolicy.transmit?(delta, map.tick_ms) do
        push(socket, "world_delta", delta)
        {:noreply, assign(socket, :world_baseline, projected)}
      else
        # Keep the last *transmitted* baseline; subsequent updates are diffed
        # against what the client actually has, not the untransmitted tick.
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # The next world_delta is broadcast in the same ordered MapServer tick.
  # Forwarding a complete NPC entity here would duplicate that payload.
  def handle_info({:npc_movement_started, _entity},
                  %{assigns: %{world_stream: :delta_v1}} = socket) do
    {:noreply, socket}
  end

  # Flight-control input is acknowledged immediately. Send only changed
  # presentation fields, suppressing repeated mouse-control heartbeats and
  # distant ship previews; authoritative position remains tick-driven.
  def handle_info({:movement_started, entity},
                  %{assigns: %{world_stream: :delta_v1}} = socket) do
    own = Enum.find(socket.assigns.world_baseline.entities, fn candidate ->
      Map.get(candidate, :player_id) == socket.assigns.current_player_id
    end)

    if own && Map.get(entity, :id) != own.id &&
         not WorldStreamPolicy.near?(own, entity) do
      {:noreply, socket}
    else
      patch = Map.take(entity, [
        :id, :position_3d, :destination_3d, :route_waypoints_3d,
        :navigation_mode, :flight_mode, :throttle, :forward_speed,
        :attitude, :orientation, :angular_velocity, :velocity
      ])
      previews = socket.assigns[:movement_previews] || %{}

      if Map.get(previews, entity.id) === patch do
        {:noreply, socket}
      else
        push(socket, "movement_delta", patch)
        {:noreply, assign(socket, :movement_previews,
          Map.put(previews, entity.id, patch))}
      end
    end
  end

  @impl true
  def handle_info({:entity_joined, entity}, socket) do
    payload = Map.put(entity, :pilot, World.player_summary(entity.player_id))
    :ok = push(socket, "entity_joined", payload)
    {:noreply, socket}
  end

  # Contact lists are computed from each pilot's authenticated SOL position.
  # Do not relay another player's navigation/contact snapshot to this client.
  def handle_info({:solar_navigation_updated, %{player_id: player_id} = payload},
                  %{assigns: %{current_player_id: current_player_id}} = socket)
      when player_id == current_player_id do
    :ok = push(socket, "solar_navigation_updated", payload)

    # World transition is a server-owned consequence of completing an actual
    # SOL voyage. Client never selects map identity or spawn coordinates.
    # Resolve through the same region policy as authenticated joins. This
    # keeps the isolated legacy test sector and future system namespaces
    # consistent instead of guessing a planet map from the navigation status.
    region_map =
      case World.region_for_player(player_id) do
        {:ok, %{map_id: map_id}} -> map_id
        _ -> nil
      end

    if region_map && region_map != socket.assigns.map_id do
      :ok = push(socket, "world_region_changed", %{map_id: region_map})
    end

    {:noreply, socket}
  end

  # A close pass is private to the pilot whose SOL path intersects a
  # persistent vessel. Never broadcast another pilot's encounter details.
  def handle_info({:solar_encounter_started, %{player_id: player_id} = payload},
                  %{assigns: %{current_player_id: current_player_id}} = socket)
      when player_id == current_player_id do
    :ok = push(socket, "solar_encounter_started", payload)
    {:noreply, socket}
  end

  def handle_info({:solar_encounter_started, _payload}, socket),
    do: {:noreply, socket}

  def handle_info({:solar_navigation_updated, _payload}, socket),
    do: {:noreply, socket}

  # A player destroyed during interception loses that SOL course rather
  # than remaining indefinitely trapped in a tactical hold. This server-only
  # failure path is authorized by the map's real destroyed ship state.
  def handle_info({:entity_destroyed,
                   %{entity: %{kind: :player, player_id: player_id}} = payload},
                  %{assigns: %{current_player_id: current_player_id}} = socket)
      when player_id == current_player_id do
    case World.solar_snapshot(socket.assigns.world_session_id) do
      {:ok, %{tactical_encounter: %{id: encounter_id}}} ->
        _ = World.solar_finish_tactical(
          socket.assigns.world_session_id, encounter_id, :defeat)
      _ -> :ok
    end
    :ok = push(socket, "entity_destroyed", payload)
    {:noreply, socket}
  end

  # The NPC death event comes from MapServer AFTER authoritative damage
  # and removal. Victory is verified against that map before the held SOL
  # voyage can resume; a forged client event cannot award a win.
  def handle_info({:entity_destroyed, %{entity: %{kind: :npc}} = payload}, socket) do
    case World.solar_snapshot(socket.assigns.world_session_id) do
      {:ok, %{tactical_encounter: %{id: encounter_id}}} ->
        _ = World.solar_finish_tactical(
          socket.assigns.world_session_id, encounter_id, :victory)
      _ -> :ok
    end

    :ok = push(socket, "entity_destroyed", payload)
    {:noreply, socket}
  end

  # This is a server-generated MapServer damage event, never a socket command.
  # Only the attacking pilot's own channel can record the faction consequence.
  def handle_info({:laser_fired, payload}, socket) do
    case World.record_tactical_hit(socket.assigns.world_session_id, payload) do
      {:ok, %{applied?: true} = effect} ->
        push(socket, "solar_faction_hit", effect)

      _ ->
        :ok
    end

    push(socket, "laser_fired", payload)
    {:noreply, socket}
  end

  def handle_info({event, payload}, socket)
      when event in [
             :entity_left,
             :movement_started,
             :world_state,
             :npc_spawned,
             :npc_movement_started,
             :npc_state_changed,
             :target_selected,
             :target_cleared,
             :combat_engaged,
             :combat_disengaged,
             :laser_fired,
             :planetary_proximity_changed,
             :entity_destroyed
           ] do
    :ok = push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:world_session_id] do
      nil -> :ok
      session_id -> World.disconnect(session_id)
    end

    :ok
  end

  defp finish_join(socket, map_id, session, status, payload) do
    with {:ok, snapshot} <- World.snapshot(map_id),
         {:ok, solar_navigation} <- World.solar_snapshot(session.id) do
        player_ids =
          snapshot.entities
          |> Enum.filter(&(&1.kind == :player))
          |> Enum.map(& &1.player_id)

        response = %{
          map: snapshot,
          solar_navigation: solar_navigation,
          player: status,
          hotbar: World.action_hotbar(),
          pilots: World.player_summaries(player_ids)
        }

        delta? = Map.get(payload, "stream") == "delta_v1"
        response = if delta?, do: Map.put(response, :stream, "delta_v1"), else: response

        {:ok, response,
         socket
         |> assign(:map_id, map_id)
         |> assign(:world_session_id, session.id)
         |> assign(:world_stream, if(delta?, do: :delta_v1, else: :full))
         |> assign(:world_baseline, snapshot)
         |> assign(:movement_previews, %{})}
    else
      {:error, reason} ->
        _result = World.disconnect(session.id)
        {:error, %{reason: error_reason(reason)}}
    end
  end

  defp error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_reason(reason), do: inspect(reason)
end
