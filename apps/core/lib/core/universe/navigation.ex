defmodule Core.Universe.Navigation do
  @moduledoc """
  Authoritative, supervised system-level travel state.

  This first slice supports a single system (SOL), one destination per pilot,
  Earth as a new pilot's start location, and bounded demo transit durations.
  Navigation and map-space combat are separate: no AU values are mapped into
  Sector 1-1 coordinates and travel alone never creates an NPC encounter.

  Transits are ephemeral per server runtime and progress even when a user
  disconnects while the supervised world stays up. Persistent locations,
  true orbital positions, physical transit and encounter generation are later
  milestones. Never accept player_id from the browser payload.
  """

  use GenServer

  alias Core.Universe.Sol
  alias Core.World.EventSink

  @tick_ms 1_000
  @system_id "sol"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec snapshot(GenServer.server(), pos_integer()) :: {:ok, map()}
  def snapshot(server, player_id) when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:snapshot, player_id})
  end

  @spec set_course(GenServer.server(), pos_integer(), term()) :: {:ok, map()} | {:error, atom()}
  def set_course(server, player_id, body_id)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:set_course, player_id, body_id})
  end

  @spec cancel_course(GenServer.server(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def cancel_course(server, player_id) when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:cancel_course, player_id})
  end

  @doc "Deterministic server test hook; never exposed to client channels."
  @spec tick(GenServer.server()) :: :ok
  def tick(server), do: GenServer.call(server, :tick)

  @impl true
  def init(opts) do
    tick_ms = Keyword.get(opts, :tick_ms, @tick_ms)
    if not (is_integer(tick_ms) and tick_ms > 0) do
      raise ArgumentError, "Solar Navigation tick_ms must be positive"
    end

    state = %{
      voyages: %{},
      tick_ms: tick_ms,
      auto_tick?: Keyword.get(opts, :auto_tick, true),
      event_sink: Keyword.fetch!(opts, :event_sink)
    }
    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:snapshot, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    {:reply, {:ok, public(voyage)}, state}
  end

  def handle_call({:set_course, player_id, destination_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      not Sol.destination?(destination_id) ->
        {:reply, {:error, :invalid_solar_destination}, state}

      voyage.status == :traveling ->
        {:reply, {:error, :already_traveling}, state}

      voyage.location_id == destination_id ->
        {:reply, {:error, :already_at_destination}, state}

      true ->
        duration_ms = Sol.travel_duration_ms(voyage.location_id, destination_id)
        updated = %{voyage |
          origin_id: voyage.location_id,
          destination_id: destination_id,
          status: :traveling,
          elapsed_ms: 0,
          duration_ms: duration_ms
        }
        state = put_voyage(state, player_id, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated)}, state}
    end
  end

  def handle_call({:cancel_course, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    if voyage.status != :traveling do
      {:reply, {:error, :no_active_course}, state}
    else
      # V1 travel is a region-to-region transit, not local free flight.
      # An aborted course stays at its departure region.
      updated = idle(voyage.location_id)
      state = put_voyage(state, player_id, updated)
      broadcast(state, player_id, updated)
      {:reply, {:ok, public(updated)}, state}
    end
  end

  def handle_call(:tick, _from, state) do
    {:reply, :ok, advance(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, state |> advance() |> schedule()}
  end

  defp ensure_player(state, player_id) do
    case Map.fetch(state.voyages, player_id) do
      {:ok, voyage} -> {voyage, state}
      :error ->
        voyage = idle("earth")
        {voyage, put_voyage(state, player_id, voyage)}
    end
  end

  defp idle(location_id) do
    %{system_id: @system_id, status: :idle, location_id: location_id,
      origin_id: location_id, destination_id: nil, elapsed_ms: 0,
      duration_ms: 0}
  end

  defp put_voyage(state, player_id, voyage),
    do: %{state | voyages: Map.put(state.voyages, player_id, voyage)}

  defp advance(state) do
    Enum.reduce(state.voyages, state, fn
      {player_id, %{status: :traveling} = voyage}, current ->
        elapsed = min(voyage.duration_ms, voyage.elapsed_ms + state.tick_ms)
        updated =
          if elapsed >= voyage.duration_ms do
            idle(voyage.destination_id)
          else
            %{voyage | elapsed_ms: elapsed}
          end
        current = put_voyage(current, player_id, updated)
        broadcast(current, player_id, updated)
        current

      {_player_id, _voyage}, current -> current
    end)
  end

  defp public(voyage) do
    progress =
      if voyage.status == :traveling and voyage.duration_ms > 0 do
        voyage.elapsed_ms / voyage.duration_ms
      else
        0.0
      end

    Map.merge(voyage, %{
      progress: progress,
      remaining_ms: max(0, voyage.duration_ms - voyage.elapsed_ms)
    })
  end

  defp broadcast(state, player_id, voyage) do
    EventSink.dispatch(state.event_sink, "1-1", :solar_navigation_updated, %{
      player_id: player_id,
      navigation: public(voyage)
    })
  end

  defp schedule(%{auto_tick?: true, tick_ms: tick_ms} = state) do
    Process.send_after(self(), :tick, tick_ms)
    state
  end
  defp schedule(state), do: state
end
