defmodule Core.Universe.Navigation do
  @moduledoc """
  Authoritative, supervised system-level travel state.

  This first slice supports a single system (SOL), one destination per pilot,
  Earth as a new pilot's start location, and real-time sublight interplanetary
  cruise through compressed game-scale system coordinates.
  Navigation and map-space combat are separate: no AU values are mapped into
  Sector 1-1 coordinates. Strategic traffic runs continuously even when no player is connected;
  close passes produce server-held, hailable decisions with genuine
  server-owned relative positions, but not tactical combat NPC instances.

  Voyages and traffic persist within the supervised server runtime and
  advance independently of player sessions. Database persistence across
  restarts, live orbital positions and tactical encounter handoffs remain
  future milestones. Never accept player_id from a browser payload.
  """

  use GenServer

  alias Core.Universe.Sol
  alias Core.Universe.PlanetaryView
  alias Core.Universe.EncounterDirector
  alias Core.Universe.Traffic
  alias Core.Universe.Territory
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

  @doc "Resolve the exact pending close pass for this authenticated pilot."
  @spec resolve_encounter(GenServer.server(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, atom()}
  def resolve_encounter(server, player_id, encounter_id, choice)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:resolve_encounter, player_id, encounter_id, choice})
  end

  @doc "Hail an in-range contact; identity and position come from the server."
  @spec hail(GenServer.server(), pos_integer(), term()) :: {:ok, map()} | {:error, atom()}
  def hail(server, player_id, contact_id)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:hail, player_id, contact_id})
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
      traffic: Keyword.get(opts, :traffic, Traffic.seed()),
      encountered: %{},
      # Server-owned reputation fixtures until the faction ledger is connected.
      # Never supplied by Phoenix client payloads or exposed in public snapshots.
      pilot_reputations: Keyword.get(opts, :pilot_reputations, %{}),
      # Isolated Navigation tests opt in; the actual world supervisor enables
      # procedural shared contacts so real departures are encounter-capable.
      procedural_contact_chance: Keyword.get(opts, :procedural_contact_chance, 0.0),
      next_contact_serial: 1,
      tick_ms: tick_ms,
      auto_tick?: Keyword.get(opts, :auto_tick, true),
      event_sink: Keyword.fetch!(opts, :event_sink)
    }
    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:snapshot, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    {:reply, {:ok, public(voyage, state, player_id)}, state}
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
        distance_km = Sol.cruise_distance_km(voyage.location_id, destination_id)
        {:ok, destination_position} = Sol.game_position_km(destination_id)
        updated = %{voyage |
          origin_id: voyage.location_id,
          destination_id: destination_id,
          voyage_number: voyage.voyage_number + 1,
          origin_position_km: voyage.position_km,
          destination_position_km: destination_position,
          propulsion_mode: :interplanetary_cruise,
          cruise_speed_km_s: Sol.cruise_speed_km_s(),
          travel_distance_km: distance_km,
          distance_travelled_km: 0.0,
          status: :traveling,
          pending_encounter: nil,
          elapsed_ms: 0,
          duration_ms: duration_ms
        }
        state = put_voyage(state, player_id, updated)
        state = maybe_launch_cruise_contact(state, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:cancel_course, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      voyage.status != :traveling ->
        {:reply, {:error, :no_active_course}, state}

      voyage.pending_encounter != nil ->
        {:reply, {:error, :encounter_decision_required}, state}

      true ->
        # An aborted course stays at its departure region. Preserve the last
        # completed arrival provenance: canceling a NEW route must not invent
        # a different approach direction if the pilot reconnects afterward.
        updated = %{idle(voyage.location_id) |
          arrival_origin_id: voyage.arrival_origin_id,
          voyage_number: voyage.voyage_number}
        state = put_voyage(state, player_id, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:resolve_encounter, player_id, encounter_id, choice}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      voyage.pending_encounter == nil ->
        {:reply, {:error, :no_pending_encounter}, state}

      not is_binary(encounter_id) or voyage.pending_encounter.id != encounter_id ->
        {:reply, {:error, :encounter_mismatch}, state}

      choice != :continue ->
        {:reply, {:error, :invalid_encounter_choice}, state}

      true ->
        updated = %{voyage | pending_encounter: nil}
        state = put_voyage(state, player_id, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:hail, player_id, contact_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    # Once the pilot has paused for this exact encounter, keep the established
    # communications channel usable even if the real vessel flies beyond
    # sensor range. Unrelated ships still require normal physical proximity.
    response =
      case voyage.pending_encounter do
        %{contact_id: ^contact_id} ->
          Traffic.hail_established(state.traffic, contact_id)

        _ ->
          Traffic.hail(state.traffic, voyage.position_km, contact_id)
      end

    {:reply, response, state}
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
    {:ok, position_km} = Sol.game_position_km(location_id)
    %{system_id: @system_id, status: :idle, location_id: location_id,
      origin_id: location_id, destination_id: nil,
      arrival_origin_id: nil, voyage_number: 0,
      propulsion_mode: :conventional,
      origin_position_km: position_km, position_km: position_km,
      destination_position_km: nil,
      pending_encounter: nil,
      cruise_speed_km_s: 0.0,
      travel_distance_km: 0.0, distance_travelled_km: 0.0,
      elapsed_ms: 0, duration_ms: 0}
  end

  defp put_voyage(state, player_id, voyage),
    do: %{state | voyages: Map.put(state.voyages, player_id, voyage)}

  defp advance(state) do
    old_traffic = state.traffic
    # Strategic traffic advances even if no pilot has ever joined.
    state = %{state | traffic: Traffic.advance(state.traffic, state.tick_ms)}

    Enum.reduce(state.voyages, state, fn
      {player_id, %{status: :traveling} = voyage}, current ->
        updated =
          if voyage.pending_encounter != nil do
            # Only this pilot's voyage is stopped. The shared clock, other
            # pilots and independent NPC traffic continue moving.
            voyage
          else
            elapsed = min(voyage.duration_ms, voyage.elapsed_ms + state.tick_ms)
            distance_covered = min(voyage.travel_distance_km,
              voyage.cruise_speed_km_s * elapsed / 1_000.0)

            if distance_covered >= voyage.travel_distance_km do
              %{idle(voyage.destination_id) |
                arrival_origin_id: voyage.origin_id,
                voyage_number: voyage.voyage_number}
            else
              fraction = distance_covered / voyage.travel_distance_km
              %{voyage | elapsed_ms: elapsed,
                distance_travelled_km: distance_covered,
                position_km: Sol.interpolate_game_position(
                  voyage.origin_position_km, voyage.destination_position_km, fraction)}
            end
          end

        current = put_voyage(current, player_id, updated)
        current = announce_encounter(current, player_id, updated)
        # announce_encounter may have added a hold to the stored voyage.
        # Broadcast THAT authoritative value, never the stale pre-hold map.
        broadcast(current, player_id, Map.fetch!(current.voyages, player_id))
        current

      {player_id, voyage}, current ->
        # Idle pilots receive contact motion/exit updates only while there is
        # something on their sensors. Other players do not cause spawns.
        before = Traffic.contacts(old_traffic, voyage.position_km)
        after_contacts = Traffic.contacts(current.traffic, voyage.position_km)
        if before != [] or after_contacts != [] do
          broadcast(current, player_id, voyage)
        end
        current
    end)
  end

  defp public(voyage, state, player_id) do
    traffic = state.traffic
    {progress, remaining_ms} =
      if voyage.status == :traveling and voyage.travel_distance_km > 0 do
        remaining_km = max(0.0, voyage.travel_distance_km - voyage.distance_travelled_km)
        {voyage.distance_travelled_km / voyage.travel_distance_km,
         ceil(remaining_km / voyage.cruise_speed_km_s) * 1_000}
      else
        {0.0, 0}
      end

    # Read-only server-computed jurisdiction. Do not expose patrol pressure,
    # private reputations or interception rolls in the navigation snapshot.
    {:ok, jurisdiction} = Territory.classify(voyage.position_km)

    Map.merge(voyage, %{
      progress: progress,
      remaining_ms: remaining_ms,
      contacts: Traffic.contacts(traffic, voyage.position_km),
      encounter: EncounterDirector.evaluate(traffic, voyage, reputations_for(state, player_id)),
      cruise_paused: voyage.pending_encounter != nil,
      planetary_view: PlanetaryView.describe(voyage),
      territory: %{
        status: jurisdiction.status,
        faction_ids: Enum.map(jurisdiction.claims, & &1.faction_id)
      }
    })
  end

  # Procedural contacts are genuinely positioned vessels in the shared
  # traffic map, not fabricated UI notifications or per-client NPC clones.
  # Their server-generated reverse route crosses the player's lane. For
  # current playtesting the supervisor chooses chance=1.0; it can be tuned
  # without changing the encounter protocol.
  defp maybe_launch_cruise_contact(state, voyage) do
    chance = state.procedural_contact_chance

    if is_number(chance) and chance > 0 and chance <= 1 and
         (chance == 1 or :rand.uniform() <= chance) do
      serial = state.next_contact_serial
      kind = Enum.at([:independent_trader, :patrol, :raider], :rand.uniform(3) - 1)
      phase = 0.43 + :rand.uniform() * 0.14

      case Traffic.launch_contact(state.traffic, voyage.origin_id,
             voyage.destination_id, serial, kind, phase) do
        {:ok, traffic} ->
          %{state | traffic: traffic, next_contact_serial: serial + 1}

        {:error, _reason} ->
          state
      end
    else
      state
    end
  end

  defp reputations_for(state, player_id) do
    Map.get(state.pilot_reputations, player_id, %{})
  end

  # A real traffic vessel can pass multiple pilots. The flyby is published
  # only on a pilot's first proximity crossing for that vessel/voyage;
  # repeated SOL snapshots still carry its current relative position.
  defp announce_encounter(state, _player_id, %{pending_encounter: pending})
       when not is_nil(pending), do: state

  defp announce_encounter(state, player_id, voyage) do
    case EncounterDirector.evaluate(state.traffic, voyage, reputations_for(state, player_id)) do
      nil -> state
      encounter ->
        seen = Map.get(state.encountered, player_id, MapSet.new())
        if MapSet.member?(seen, encounter.id) do
          state
        else
          # Persist the decision in supervised state before announcing it;
          # reconnecting pilots see the same pending encounter.
          state = put_voyage(state, player_id, %{voyage | pending_encounter: encounter})
          state = %{state | encountered: Map.put(state.encountered, player_id,
            MapSet.put(seen, encounter.id))}
          EventSink.dispatch(state.event_sink, "sol", :solar_encounter_started, %{
            player_id: player_id,
            encounter: encounter
          })
          state
        end
    end
  end

  defp broadcast(state, player_id, voyage) do
    EventSink.dispatch(state.event_sink, "sol", :solar_navigation_updated, %{
      player_id: player_id,
      navigation: public(voyage, state, player_id)
    })
  end

  defp schedule(%{auto_tick?: true, tick_ms: tick_ms} = state) do
    Process.send_after(self(), :tick, tick_ms)
    state
  end
  defp schedule(state), do: state
end
