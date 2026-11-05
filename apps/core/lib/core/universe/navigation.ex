defmodule Core.Universe.Navigation do
  @moduledoc """
  Authoritative, supervised system-level travel state.

  This first slice supports a single system (SOL), one destination per pilot,
  Earth as a new pilot's start location, and real-time sublight interplanetary
  cruise through compressed game-scale system coordinates.
  Navigation and map-space combat are separate: no AU values are mapped into
  Sector 1-1 coordinates. Strategic traffic runs continuously even when no player
  is connected; close passes are held against shared, server-owned vessels,
  with exclusive tactical leases and damage reconciliation on settlement.

  Voyages and traffic persist within the supervised server runtime and
  advance independently of player sessions. Database persistence across
  restarts, live orbital positions and shared tactical arenas remain
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


  @doc "Suspend interplanetary drive at its actual SOL position for conventional free flight."
  @spec enter_free_flight(GenServer.server(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def enter_free_flight(server, player_id) when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:enter_free_flight, player_id})
  end

  @doc "Reengage automated cruise after the flight server confirms a surviving ship."
  @spec resume_cruise(GenServer.server(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def resume_cruise(server, player_id) when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:resume_cruise, player_id})
  end

  @doc "Resolve the exact pending close pass for this authenticated pilot."
  @spec resolve_encounter(GenServer.server(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, atom()}
  def resolve_encounter(server, player_id, encounter_id, choice)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:resolve_encounter, player_id, encounter_id, choice})
  end

  @doc "Enter the pilot's held encounter (including a chosen neutral attack)."
  @spec enter_tactical(GenServer.server(), pos_integer(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def enter_tactical(server, player_id, encounter_id)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:enter_tactical, player_id, encounter_id})
  end

  @doc """
  Roll back a failed tactical spawn, or settle a map-verified outcome.
  Completed outcomes MUST include the authoritative combat report returned
  by MapServer. There is no client-facing settlement API.
  """
  @spec finish_tactical(GenServer.server(), pos_integer(), String.t(), atom()) ::
          {:ok, map()} | {:error, atom()}
  def finish_tactical(server, player_id, encounter_id, outcome)
      when is_integer(player_id) and player_id > 0 do
    finish_tactical(server, player_id, encounter_id, outcome, nil)
  end

  @spec finish_tactical(GenServer.server(), pos_integer(), String.t(), atom(), map() | nil) ::
          {:ok, map()} | {:error, atom()}
  def finish_tactical(server, player_id, encounter_id, outcome, report)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:finish_tactical, player_id, encounter_id, outcome, report})
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
      # At most one pilot owns a given physical vessel during a tactical
      # encounter. Leases are bound to its current traffic voyage number.
      tactical_claims: %{},
      # Exact receipts permit retry when map cleanup fails after settlement.
      settled_tactical: %{},
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


  def handle_call({:enter_free_flight, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      voyage.status != :traveling ->
        {:reply, {:error, :no_active_course}, state}
      voyage.free_flight ->
        {:reply, {:error, :already_in_free_flight}, state}
      voyage.pending_encounter != nil or voyage.tactical_encounter != nil ->
        {:reply, {:error, :encounter_decision_required}, state}
      true ->
        updated = %{voyage | free_flight: true, propulsion_mode: :conventional}
        state = put_voyage(state, player_id, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:resume_cruise, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    if voyage.status == :traveling and voyage.free_flight and
         voyage.tactical_encounter == nil do
      updated = %{voyage | free_flight: false, propulsion_mode: :interplanetary_cruise}
      state = put_voyage(state, player_id, updated)
      broadcast(state, player_id, updated)
      {:reply, {:ok, public(updated, state, player_id)}, state}
    else
      {:reply, {:error, :not_in_free_flight}, state}
    end
  end

  def handle_call({:set_course, player_id, target}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    with {:ok, destination_id, destination_position} <- resolve_destination(target) do
      distance_km = position_distance(voyage.position_km, destination_position)

      cond do
        voyage.status == :traveling ->
          {:reply, {:error, :already_traveling}, state}

        distance_km < 1.0 ->
          {:reply, {:error, :already_at_destination}, state}

        true ->
          duration_ms = max(1, ceil(distance_km / Sol.cruise_speed_km_s())) * 1_000
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
            tactical_encounter: nil,
            elapsed_ms: 0,
            duration_ms: duration_ms
          }
          state = put_voyage(state, player_id, updated)
          state = maybe_launch_cruise_contact(state, updated)
          broadcast(state, player_id, updated)
          {:reply, {:ok, public(updated, state, player_id)}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_course, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      voyage.status != :traveling ->
        {:reply, {:error, :no_active_course}, state}

      voyage.pending_encounter != nil ->
        {:reply, {:error, :encounter_decision_required}, state}

      voyage.free_flight ->
        {:reply, {:error, :free_flight_active}, state}

      true ->
        # Aborting a voyage must not teleport the ship back to its origin.
        updated =
          if voyage.position_km == voyage.origin_position_km and
               is_binary(voyage.location_id) do
            %{idle(voyage.location_id) |
              arrival_origin_id: voyage.arrival_origin_id,
              voyage_number: voyage.voyage_number}
          else
            idle_at(voyage.position_km, voyage)
          end
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

      voyage.tactical_encounter != nil ->
        {:reply, {:error, :tactical_encounter_active}, state}

      true ->
        updated = %{voyage | pending_encounter: nil}
        state = put_voyage(state, player_id, updated)
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:enter_tactical, player_id, encounter_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    cond do
      voyage.status != :traveling or voyage.pending_encounter == nil ->
        {:reply, {:error, :no_pending_encounter}, state}

      not is_binary(encounter_id) or voyage.pending_encounter.id != encounter_id ->
        {:reply, {:error, :encounter_mismatch}, state}

      voyage.tactical_encounter != nil ->
        {:reply, {:error, :tactical_encounter_active}, state}

      voyage.pending_encounter.classification not in
          [:hostile_contact, :patrol_attention, :neutral_flyby] ->
        {:reply, {:error, :not_a_combat_encounter}, state}

      not Map.has_key?(state.traffic, voyage.pending_encounter.contact_id) ->
        {:reply, {:error, :vessel_unavailable}, state}

      Map.has_key?(state.tactical_claims, voyage.pending_encounter.contact_id) ->
        {:reply, {:error, :vessel_engaged}, state}

      not available_vessel?(state.traffic[voyage.pending_encounter.contact_id],
            voyage.pending_encounter) ->
        {:reply, {:error, :vessel_unavailable}, state}

      true ->
        contact = Map.fetch!(state.traffic, voyage.pending_encounter.contact_id)
        # Retain pending_encounter as the authoritative suspended decision.
        # The UI shows the combat cockpit instead of the modal during combat.
        tactical = %{id: encounter_id, contact_id: contact.id,
          voyage_number: contact.voyage_number,
          call_sign: contact.call_sign,
          ship_class: contact.ship_class,
          # MapServer receives this authoritative initial combat condition.
          # It must never create a fresh, fully repaired clone.
          combat: contact.combat,
          # Both endpoints came from the shared SOL vessel when the close
          # pass was detected. No client can submit or overwrite the route.
          course: %{
            origin_id: voyage.pending_encounter.origin_id,
            destination_id: voyage.pending_encounter.destination_id
          },
          classification: voyage.pending_encounter.classification}
        updated = %{voyage | tactical_encounter: tactical}
        state = put_voyage(state, player_id, updated)
        state = %{state | tactical_claims: Map.put(state.tactical_claims,
          contact.id, %{player_id: player_id, encounter_id: encounter_id,
            voyage_number: contact.voyage_number})}
        broadcast(state, player_id, updated)
        {:reply, {:ok, public(updated, state, player_id)}, state}
    end
  end

  def handle_call({:finish_tactical, player_id, encounter_id, outcome, report},
                  _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    receipt = Map.get(state.settled_tactical, {player_id, encounter_id})

    cond do
      receipt == %{outcome: outcome, report: report} ->
        {:reply, {:ok, public(voyage, state, player_id)}, state}

      receipt != nil ->
        {:reply, {:error, :tactical_settlement_conflict}, state}

      not is_map(voyage.tactical_encounter) ->
        {:reply, {:error, :no_tactical_encounter}, state}

      voyage.tactical_encounter.id != encounter_id ->
        {:reply, {:error, :encounter_mismatch}, state}

      outcome not in [:rollback, :victory, :retreat, :defeat, :escaped, :surrender] ->
        {:reply, {:error, :invalid_encounter_outcome}, state}

      outcome != :rollback and not is_map(report) ->
        {:reply, {:error, :tactical_report_required}, state}

      outcome != :rollback and not is_map(Map.get(report, :combat)) ->
        {:reply, {:error, :tactical_report_required}, state}

      outcome != :rollback and
          (Map.get(report, :contact_id) != voyage.tactical_encounter.contact_id or
           Map.get(report, :voyage_number) != voyage.tactical_encounter.voyage_number or
           Map.get(report, :encounter_id) != encounter_id) ->
        {:reply, {:error, :tactical_report_mismatch}, state}

      true ->
        tactical = voyage.tactical_encounter
        claim = Map.get(state.tactical_claims, tactical.contact_id)

        if claim != %{player_id: player_id, encounter_id: encounter_id,
                       voyage_number: tactical.voyage_number} do
          {:reply, {:error, :tactical_claim_mismatch}, state}
        else
          settlement =
            if outcome == :rollback do
              {:ok, state.traffic}
            else
              Traffic.settle(state.traffic,
                %{contact_id: tactical.contact_id, encounter_id: encounter_id,
                  voyage_number: tactical.voyage_number},
                report.combat, outcome)
            end

          case settlement do
            {:error, reason} ->
              {:reply, {:error, reason}, state}

            {:ok, traffic} ->
              updated =
                case outcome do
                  :rollback -> %{voyage | tactical_encounter: nil}

                  :defeat ->
                    %{idle(voyage.location_id) |
                      arrival_origin_id: voyage.arrival_origin_id,
                      voyage_number: voyage.voyage_number}

                  _ ->
                    %{voyage | tactical_encounter: nil, pending_encounter: nil}
                end

              receipts =
                if outcome == :rollback do
                  state.settled_tactical
                else
                  Map.put(state.settled_tactical, {player_id, encounter_id},
                    %{outcome: outcome, report: report})
                end

              state = %{state | traffic: traffic, settled_tactical: receipts,
                tactical_claims: Map.delete(state.tactical_claims, tactical.contact_id)}
              state = put_voyage(state, player_id, updated)
              broadcast(state, player_id, updated)
              {:reply, {:ok, public(updated, state, player_id)}, state}
          end
        end
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

  defp resolve_destination(id) when is_binary(id) do
    if Sol.destination?(id) do
      {:ok, position} = Sol.game_position_km(id)
      {:ok, id, position}
    else
      {:error, :invalid_solar_destination}
    end
  end

  defp resolve_destination(%{} = point) do
    case Sol.waypoint(point) do
      {:ok, position} -> {:ok, nil, position}
      error -> error
    end
  end

  defp resolve_destination(_), do: {:error, :invalid_solar_destination}

  defp position_distance(a, b) do
    :math.sqrt(:math.pow(a.x - b.x, 2) + :math.pow(a.y - b.y, 2) +
      :math.pow(a.z - b.z, 2))
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
             tactical_encounter: nil,
       free_flight: false,
       cruise_speed_km_s: 0.0,
      travel_distance_km: 0.0, distance_travelled_km: 0.0,
      elapsed_ms: 0, duration_ms: 0}
  end

  # An unmarked destination is a genuine SOL position, not a planet.
  defp idle_at(position, voyage) do
    %{idle("earth") |
      location_id: nil, origin_id: nil, arrival_origin_id: nil,
      origin_position_km: position, position_km: position,
      voyage_number: voyage.voyage_number}
  end

  defp put_voyage(state, player_id, voyage),
    do: %{state | voyages: Map.put(state.voyages, player_id, voyage)}

  defp advance(state) do
    old_traffic = state.traffic
    # Strategic traffic advances even if no pilot has ever joined.
    held = state.tactical_claims |> Map.keys() |> MapSet.new()
    state = %{state | traffic: Traffic.advance(state.traffic, state.tick_ms, held)}

    Enum.reduce(state.voyages, state, fn
      {player_id, %{status: :traveling} = voyage}, current ->
        updated =
          if voyage.pending_encounter != nil or voyage.free_flight do
            # Only this pilot's voyage is stopped. The shared clock, other
            # pilots and independent NPC traffic continue moving.
            voyage
          else
            elapsed = min(voyage.duration_ms, voyage.elapsed_ms + state.tick_ms)
            distance_covered = min(voyage.travel_distance_km,
              voyage.cruise_speed_km_s * elapsed / 1_000.0)

            if distance_covered >= voyage.travel_distance_km do
              if is_binary(voyage.destination_id) do
                %{idle(voyage.destination_id) |
                  arrival_origin_id: voyage.origin_id,
                  voyage_number: voyage.voyage_number}
              else
                idle_at(voyage.destination_position_km, voyage)
              end
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
      cruise_paused: voyage.pending_encounter != nil or voyage.free_flight,
      # Tactical combat currently takes place in the pilot's existing
      # orbital map. Show that map's ACTUAL planet and collision geometry,
      # not the approaching destination (which would be misleading).
      planetary_view: if(voyage.free_flight, do: nil,
        else: PlanetaryView.describe(
          if(voyage.tactical_encounter, do: %{voyage | status: :idle}, else: voyage))),
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

  defp available_vessel?(contact, encounter) when is_map(contact) do
    combat = Map.get(contact, :combat, %{})

    Map.get(contact, :voyage_number) == voyage_number(encounter.id) and
      Map.get(contact, :state) == :in_transit and
      is_map(combat) and Map.get(combat, :status) == :alive and
      is_integer(Map.get(combat, :hull)) and combat.hull > 0
  end

  defp available_vessel?(_contact, _encounter), do: false

  # The original encounter ID embeds the strategic voyage number; refuse
  # entry if that vessel has since completed the identified voyage.
  defp voyage_number(encounter_id) do
    case String.split(encounter_id, ":") |> List.last() |> Integer.parse() do
      {value, ""} -> value
      _ -> -1
    end
  end

  defp reputations_for(state, player_id) do
    Map.get(state.pilot_reputations, player_id, %{})
  end

  # A real traffic vessel can pass multiple pilots. The flyby is published
  # only on a pilot's first proximity crossing for that vessel/voyage;
  # repeated SOL snapshots still carry its current relative position.
  defp announce_encounter(state, _player_id, %{free_flight: true}), do: state

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
