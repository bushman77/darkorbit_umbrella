defmodule DarkorbitWeb.HelmetManager do
  @moduledoc """
  Ephemeral pairing invitations and headset presence around persisted device
  registrations. The invitation exists only while the Atlas HMD panel is open.
  No QR timeout and no expiration of registered helmets.
  """
  use GenServer

  alias Darkorbit.Helmets
  alias DarkorbitWeb.Endpoint

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def status(player_id), do: GenServer.call(__MODULE__, {:status, player_id})
  def open_pairing(player_id), do: GenServer.call(__MODULE__, {:open_pairing, player_id})
  def cancel_pairing(player_id), do: GenServer.call(__MODULE__, {:cancel_pairing, player_id})
  def redeem(code, name), do: GenServer.call(__MODULE__, {:redeem, code, name})
  def forget(player_id), do: GenServer.call(__MODULE__, {:forget, player_id})
  def set_mode(player_id, mode) when mode in [:standby, :combat],
    do: GenServer.call(__MODULE__, {:mode, player_id, mode})
  def viewer_online(pid, player_id, device_id),
    do: GenServer.call(__MODULE__, {:viewer_online, pid, player_id, device_id})
  def viewer_offline(pid), do: GenServer.call(__MODULE__, {:viewer_offline, pid})
  def rendering(pid, active), do: GenServer.call(__MODULE__, {:rendering, pid, active})

  # The laptop may adjust alignment only in an active cockpit session. The
  # phone owns the calibrated values and persists them in its local storage.
  def adjust_alignment(player_id, axis, direction)
      when axis in [:gap, :eye_sep] and direction in [-1, 1] do
    GenServer.call(__MODULE__, {:adjust_alignment, player_id, axis, direction})
  end

  def report_alignment(pid, gap_px, separation_mm)
      when is_integer(gap_px) and gap_px in 0..80 and
           is_integer(separation_mm) and separation_mm in 40..85 do
    GenServer.call(__MODULE__, {:alignment_report, pid, gap_px, separation_mm})
  end

  @impl true
  def init(_), do: {:ok, %{pending: %{}, modes: %{}, viewers: %{}}}

  @impl true
  def handle_call({:status, player_id}, _from, state),
    do: {:reply, public_status(state, player_id), state}

  def handle_call({:open_pairing, player_id}, _from, state) do
    if Helmets.device(player_id) do
      {:reply, {:error, :already_paired}, state}
    else
      code = Map.get(state.pending, player_id) ||
        Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      next = %{state | pending: Map.put(state.pending, player_id, code)}
      notify(next, player_id)
      {:reply, {:ok, code}, next}
    end
  end

  def handle_call({:cancel_pairing, player_id}, _from, state) do
    next = %{state | pending: Map.delete(state.pending, player_id)}
    notify(next, player_id)
    {:reply, :ok, next}
  end

  def handle_call({:redeem, code, name}, _from, state) do
    owner = Enum.find_value(state.pending, fn {id, pending_code} ->
      if secure_equal?(pending_code, code), do: id
    end)

    if owner do
      case Helmets.register(owner, name) do
        {:ok, %{device: device, credential: credential}} ->
          next = %{state | pending: Map.delete(state.pending, owner)}
          notify(next, owner)
          {:reply, {:ok, %{player_id: owner, device_id: device.id,
                            credential: credential}}, next}
        {:error, _} = error -> {:reply, error, state}
      end
    else
      {:reply, {:error, :invalid_pairing}, state}
    end
  end

  def handle_call({:forget, player_id}, _from, state) do
    :ok = Helmets.forget(player_id)
    {removed, remaining} = Enum.split_with(state.viewers,
      fn {_pid, viewer} -> viewer.player_id == player_id end)
    Enum.each(removed, fn {pid, viewer} ->
      Process.demonitor(viewer.monitor, [:flush])
      send(pid, :helmet_revoked)
    end)
    next = %{state | pending: Map.delete(state.pending, player_id),
                    viewers: Map.new(remaining)}
    notify(next, player_id)
    {:reply, :ok, next}
  end

  def handle_call({:mode, player_id, mode}, _from, state) do
    next = %{state | modes: Map.put(state.modes, player_id, mode),
                    viewers: Map.new(state.viewers, fn {pid, viewer} ->
                      if viewer.player_id == player_id do
                        send(pid, {:helmet_mode, mode})
                        {pid, %{viewer | rendering: false}}
                      else
                        {pid, viewer}
                      end
                    end)}
    notify(next, player_id)
    {:reply, :ok, next}
  end

  def handle_call({:viewer_online, pid, player_id, device_id}, _from, state) do
    case Helmets.device(player_id) do
      %{id: ^device_id} ->
        monitor = Process.monitor(pid)
        viewer = %{player_id: player_id, monitor: monitor, rendering: false, alignment: nil}
        next = %{state | viewers: Map.put(state.viewers, pid, viewer)}
        notify(next, player_id)
        {:reply, {:ok, Map.get(state.modes, player_id, :standby)}, next}
      _ -> {:reply, {:error, :revoked}, state}
    end
  end

  def handle_call({:viewer_offline, pid}, _from, state) do
    {viewer, next} = remove_viewer(state, pid)
    if viewer, do: notify(next, viewer.player_id)
    {:reply, :ok, next}
  end

  def handle_call({:adjust_alignment, player_id, axis, direction}, _from, state) do
    active? = Map.get(state.modes, player_id, :standby) == :combat
    viewers =
      for {pid, viewer} <- state.viewers,
          viewer.player_id == player_id and viewer.rendering,
          do: pid

    cond do
      not active? ->
        {:reply, {:error, :not_in_cockpit}, state}

      viewers == [] ->
        {:reply, {:error, :helmet_not_rendering}, state}

      true ->
        Enum.each(viewers, &send(&1, {:helmet_alignment_adjust, axis, direction}))
        {:reply, :ok, state}
    end
  end

  def handle_call({:alignment_report, pid, gap_px, separation_mm}, _from, state) do
    case Map.fetch(state.viewers, pid) do
      {:ok, viewer} ->
        updated = %{viewer | alignment: %{eye_gap_px: gap_px, eye_sep_mm: separation_mm}}
        next = %{state | viewers: Map.put(state.viewers, pid, updated)}
        notify(next, viewer.player_id)
        {:reply, :ok, next}

      :error ->
        {:reply, {:error, :unknown_viewer}, state}
    end
  end

  def handle_call({:rendering, pid, active}, _from, state) do
    case Map.fetch(state.viewers, pid) do
      {:ok, viewer} ->
        enabled = active == true and Map.get(state.modes, viewer.player_id, :standby) == :combat
        next = %{state | viewers: Map.put(state.viewers, pid, %{viewer | rendering: enabled})}
        notify(next, viewer.player_id)
        {:reply, :ok, next}
      :error -> {:reply, {:error, :unknown_viewer}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, pid, _reason}, state) do
    case Map.get(state.viewers, pid) do
      %{monitor: ^monitor} = viewer ->
        {_viewer, next} = remove_viewer(state, pid)
        notify(next, viewer.player_id)
        {:noreply, next}
      _ -> {:noreply, state}
    end
  end

  defp remove_viewer(state, pid) do
    {viewer, viewers} = Map.pop(state.viewers, pid)
    if viewer, do: Process.demonitor(viewer.monitor, [:flush])
    {viewer, %{state | viewers: viewers}}
  end

  defp public_status(state, player_id) do
    device = Helmets.device(player_id)
    viewers = for {_pid, viewer} <- state.viewers, viewer.player_id == player_id,
                  do: viewer

    %{
      paired: device != nil,
      device_name: if(device, do: device.device_name, else: nil),
      connected: viewers != [],
      rendering: Enum.any?(viewers, & &1.rendering),
      alignment: Enum.find_value(viewers, & &1.alignment),
      mode: Map.get(state.modes, player_id, :standby),
      pairing: Map.has_key?(state.pending, player_id)
    }
  end

  defp notify(state, player_id) do
    Endpoint.broadcast("helmet:control:#{player_id}", "helmet_status",
      public_status(state, player_id))
  end

  defp secure_equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: Plug.Crypto.secure_compare(a, b)
  defp secure_equal?(_, _), do: false
end
