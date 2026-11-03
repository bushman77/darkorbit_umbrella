defmodule DarkorbitWeb.HelmetChannel do
  @moduledoc """
  Pilot-only helmet control and read-only, individually authenticated HMD feeds.
  No movement, targeting, weapon or ship-command messages exist on this channel.
  """
  use DarkorbitWeb, :channel

  alias Darkorbit.{Helmets, World}
  alias DarkorbitWeb.{HelmetManager, HelmetNetwork}

  @map_id "1-1"

  @impl true
  def join("helmet:control:" <> id, _params,
           %{assigns: %{socket_role: :pilot, current_player_id: player_id}} = socket) do
    if id == Integer.to_string(player_id) do
      {:ok, %{
        status: HelmetManager.status(player_id),
        network_hosts: HelmetNetwork.hosts()
      }, assign(socket, :helmet_role, :controller)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def join("helmet:viewer", _params,
           %{assigns: %{socket_role: :helmet, helmet_player_id: player_id,
                        helmet_device_id: device_id}} = socket) do
    case HelmetManager.viewer_online(self(), player_id, device_id) do
      {:ok, mode} ->
        send(self(), {:helmet_mode, mode})
        {:ok, %{mode: mode, player_id: player_id, calibration: Helmets.calibration(device_id)},
         socket |> assign(:helmet_role, :viewer)
                |> assign(:helmet_active, false)}
      {:error, reason} -> {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "forbidden"}}

  @impl true
  def handle_in("open_pairing", _payload,
                %{assigns: %{helmet_role: :controller, current_player_id: player_id}} = socket) do
    case HelmetManager.open_pairing(player_id) do
      {:ok, code} -> {:reply, {:ok, %{code: code}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("cancel_pairing", _payload,
                %{assigns: %{helmet_role: :controller, current_player_id: player_id}} = socket) do
    :ok = HelmetManager.cancel_pairing(player_id)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("forget", _payload,
                %{assigns: %{helmet_role: :controller, current_player_id: player_id}} = socket) do
    :ok = HelmetManager.forget(player_id)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("set_mode", %{"mode" => mode},
                %{assigns: %{helmet_role: :controller, current_player_id: player_id}} = socket)
      when mode in ["standby", "combat"] do
    :ok = HelmetManager.set_mode(player_id, String.to_existing_atom(mode))
    {:reply, {:ok, %{mode: mode}}, socket}
  end

  def handle_in("adjust_alignment", %{"axis" => axis, "direction" => direction},
                %{assigns: %{helmet_role: :controller, current_player_id: player_id}} = socket)
      when axis in ["gap", "eye_sep"] and direction in [-1, 1] do
    dimension = if axis == "gap", do: :gap, else: :eye_sep

    case HelmetManager.adjust_alignment(player_id, dimension, direction) do
      :ok -> {:reply, {:ok, %{axis: axis, direction: direction}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  # Browser saves only after input settles. This write is authenticated by
  # the helmet socket's device ID, not any client-supplied player/device ID.
  def handle_in("save_alignment", %{"eye_gap_px" => gap, "eye_sep_mm" => separation},
                %{assigns: %{helmet_role: :viewer, helmet_device_id: device_id}} = socket)
      when is_integer(gap) and gap in -160..80 and
           is_integer(separation) and separation in 40..85 do
    case Helmets.save_calibration(device_id, gap, separation) do
      {:ok, saved} -> {:reply, {:ok, saved}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("alignment_state", %{"eye_gap_px" => gap, "eye_sep_mm" => separation},
                %{assigns: %{helmet_role: :viewer}} = socket)
      when is_integer(gap) and gap in -160..80 and
           is_integer(separation) and separation in 40..85 do
    case HelmetManager.report_alignment(self(), gap, separation) do
      :ok -> {:reply, {:ok, %{}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("rendering_status", %{"rendering" => rendering},
                %{assigns: %{helmet_role: :viewer}} = socket)
      when is_boolean(rendering) do
    :ok = HelmetManager.rendering(self(), rendering)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "read_only_or_invalid_command"}}, socket}

  @impl true
  def handle_info({:helmet_mode, :combat}, socket) do
    unless socket.assigns.helmet_active do
      :ok = World.subscribe(@map_id)
      # The viewer receives only its own encounter status, not pilot commands.
      :ok = World.subscribe("sol")
    end

    push(socket, "helmet_mode", %{mode: "combat"})
    case World.snapshot(@map_id) do
      {:ok, map} ->
        push(socket, "helmet_snapshot",
          %{map: map, player_id: socket.assigns.helmet_player_id})
      {:error, _} -> push(socket, "helmet_error", %{reason: "world_unavailable"})
    end
    {:noreply, assign(socket, :helmet_active, true)}
  end

  def handle_info({:helmet_mode, :standby}, socket) do
    if socket.assigns.helmet_active do
      Phoenix.PubSub.unsubscribe(Darkorbit.PubSub, Darkorbit.World.PubSub.topic(@map_id))
      Phoenix.PubSub.unsubscribe(Darkorbit.PubSub, Darkorbit.World.PubSub.topic("sol"))
    end
    push(socket, "helmet_mode", %{mode: "standby"})
    {:noreply, assign(socket, :helmet_active, false)}
  end

  def handle_info({:world_state, map}, %{assigns: %{helmet_active: true}} = socket) do
    push(socket, "world_state", map)
    {:noreply, socket}
  end

  # Only the paired pilot's encounter reaches the read-only viewer.
  # Limit payloads to visual metadata; never forward cargo or reputation.
  def handle_info({:solar_navigation_updated,
                   %{player_id: player_id, navigation: navigation}},
                  %{assigns: %{helmet_role: :viewer, helmet_active: true,
                               helmet_player_id: helmet_player_id}} = socket)
      when player_id == helmet_player_id do
    push(socket, "helmet_encounter", helmet_encounter(navigation))
    {:noreply, socket}
  end

  def handle_info({:solar_encounter_started,
                   %{player_id: player_id, encounter: encounter}},
                  %{assigns: %{helmet_role: :viewer, helmet_active: true,
                               helmet_player_id: helmet_player_id}} = socket)
      when player_id == helmet_player_id do
    push(socket, "helmet_encounter", helmet_encounter(%{pending_encounter: encounter}))
    {:noreply, socket}
  end

  def handle_info({event, payload}, %{assigns: %{helmet_active: true}} = socket)
      when event in [:laser_fired, :npc_spawned, :entity_destroyed] do
    push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end

  def handle_info({event, _payload}, socket)
      when event in [:world_state, :laser_fired, :npc_spawned, :entity_destroyed],
      do: {:noreply, socket}

  def handle_info({:helmet_alignment_adjust, axis, direction},
                  %{assigns: %{helmet_role: :viewer, helmet_active: true}} = socket)
      when axis in [:gap, :eye_sep] and direction in [-1, 1] do
    push(socket, "helmet_alignment_adjust",
      %{axis: Atom.to_string(axis), direction: direction})
    {:noreply, socket}
  end

  def handle_info(:helmet_revoked, socket) do
    push(socket, "helmet_revoked", %{})
    {:stop, :normal, socket}
  end

  # Core.World broadcasts additional PubSub notifications (movement_started,
  # movement_stopped, etc.). They are not part of the phone's minimal display
  # feed and MUST NOT crash a viewer channel during combat.
  # In standby the channel is unsubscribed, so these do not use bandwidth.
  def handle_info({_world_event, _payload}, socket), do: {:noreply, socket}

  # Unrelated process messages must never tear down a registered HMD.
  def handle_info(_message, socket), do: {:noreply, socket}

  defp helmet_encounter(%{pending_encounter: encounter}) when is_map(encounter) do
    %{paused: true, encounter: Map.take(encounter,
      [:id, :call_sign, :kind, :classification, :distance_km])}
  end

  defp helmet_encounter(_navigation), do: %{paused: false, encounter: nil}

  @impl true
  def terminate(_reason, %{assigns: %{helmet_role: :viewer}}) do
    HelmetManager.viewer_offline(self())
    :ok
  end

  def terminate(_reason, %{assigns: %{helmet_role: :controller,
                                      current_player_id: player_id}}) do
    # A QR invitation is only valid while the controlling Atlas channel exists.
    HelmetManager.cancel_pairing(player_id)
    HelmetManager.set_mode(player_id, :standby)
    :ok
  end

  def terminate(_reason, _socket), do: :ok
end
