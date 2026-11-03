defmodule DarkorbitWeb.HelmetChannel do
  @moduledoc """
  Pilot-only helmet control and read-only, individually authenticated HMD feeds.
  No movement, targeting, weapon or ship-command messages exist on this channel.
  """
  use DarkorbitWeb, :channel

  alias Darkorbit.World
  alias DarkorbitWeb.HelmetManager

  @map_id "1-1"

  @impl true
  def join("helmet:control:" <> id, _params,
           %{assigns: %{socket_role: :pilot, current_player_id: player_id}} = socket) do
    if id == Integer.to_string(player_id) do
      {:ok, %{status: HelmetManager.status(player_id)},
       assign(socket, :helmet_role, :controller)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def join("helmet:viewer", %{"device_name" => name},
           %{assigns: %{socket_role: :pairing, pairing_code: code}} = socket) do
    with {:ok, result} <- HelmetManager.redeem(code, name),
         {:ok, mode} <- HelmetManager.viewer_online(self(), result.player_id, result.device_id) do
      send(self(), {:helmet_mode, mode})
      {:ok, %{mode: mode, player_id: result.player_id,
              credential: result.credential},
       socket |> assign(:helmet_role, :viewer)
              |> assign(:helmet_player_id, result.player_id)
              |> assign(:helmet_active, false)}
    else
      {:error, reason} -> {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  def join("helmet:viewer", _params,
           %{assigns: %{socket_role: :helmet, helmet_player_id: player_id,
                        helmet_device_id: device_id}} = socket) do
    case HelmetManager.viewer_online(self(), player_id, device_id) do
      {:ok, mode} ->
        send(self(), {:helmet_mode, mode})
        {:ok, %{mode: mode, player_id: player_id},
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
    end
    push(socket, "helmet_mode", %{mode: "standby"})
    {:noreply, assign(socket, :helmet_active, false)}
  end

  def handle_info({:world_state, map}, %{assigns: %{helmet_active: true}} = socket) do
    push(socket, "world_state", map)
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

  def handle_info(:helmet_revoked, socket) do
    push(socket, "helmet_revoked", %{})
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{helmet_role: :viewer}}) do
    HelmetManager.viewer_offline(self())
    :ok
  end

  def terminate(_reason, %{assigns: %{helmet_role: :controller,
                                      current_player_id: player_id}}) do
    # A QR invitation is only valid while the controlling Atlas channel exists.
    HelmetManager.cancel_pairing(player_id)
    :ok
  end

  def terminate(_reason, _socket), do: :ok
end
