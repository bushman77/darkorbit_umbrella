defmodule DarkorbitWeb.WorldChannel do
  use DarkorbitWeb, :channel

  alias Darkorbit.World
  alias Core.Universe.OrbitalEntry

  @impl true
  def join("world:" <> map_id, _payload,
           %{assigns: %{socket_role: :pilot}} = socket) do
    player_id = socket.assigns.current_player_id

    with {:ok, region} <- World.region_for_player(player_id) do
      if region.map_id != map_id do
        {:error, %{reason: "region_redirect", map_id: region.map_id}}
      else
        with :ok <- World.subscribe(map_id),
             :ok <- World.subscribe("sol"),
             {:ok, status} <- World.player_status(player_id, 1),
             {:ok, session} <- World.connect(player_id, 1, map_id: map_id) do
          finish_join(socket, map_id, session, status)
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

  def handle_in("solar_set_course", _payload, socket),
    do: {:reply, {:error, %{reason: "invalid_solar_destination"}}, socket}

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
    # Authentication and entity identity come solely from the channel session.
    case World.flight_controls(socket.assigns.world_session_id, input) do
      {:ok, entity} -> {:reply, {:ok, %{entity: entity}}, socket}
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
    navigation = payload.navigation
    if navigation.status == :idle do
      region_map = OrbitalEntry.map_id(navigation.location_id)
      if region_map && region_map != socket.assigns.map_id do
        :ok = push(socket, "world_region_changed", %{map_id: region_map})
      end
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

  defp finish_join(socket, map_id, session, status) do
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

        {:ok, response,
         socket
         |> assign(:map_id, map_id)
         |> assign(:world_session_id, session.id)}
    else
      {:error, reason} ->
        _result = World.disconnect(session.id)
        {:error, %{reason: error_reason(reason)}}
    end
  end

  defp error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_reason(reason), do: inspect(reason)
end
