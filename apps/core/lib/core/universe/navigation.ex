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

  Voyages advance independently of player sessions. The production supervisor
  loads and checkpoints pilot voyages via a PostgreSQL adapter. Shared
  commercial traffic remains runtime-owned. Never trust browser-supplied IDs.
  """

  use GenServer

  # Prevent a crowded shipping lane from presenting a different vessel as
  # another combat choice immediately when a tactical encounter is settled.
  @post_encounter_clearance_ms 15_000

  require Logger

  alias Core.Universe.Navigation.Checkpoint
  alias Core.Universe.Sol
  alias Core.Universe.PlanetaryView
  alias Core.Universe.EncounterDirector
  alias Core.Universe.Traffic
  alias Core.Universe.SpaceBases
  alias Core.Universe.GreenStarbase
  alias Core.Universe.TradeLanes
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
    finish_tactical(server, player_id, encounter_id, outcome, report, %{})
  end

  @spec finish_tactical(GenServer.server(), pos_integer(), String.t(),
          atom(), map() | nil, map()) :: {:ok, map()} | {:error, atom()}
  def finish_tactical(server, player_id, encounter_id, outcome, report, cargo_debit)
      when is_integer(player_id) and player_id > 0 and is_map(cargo_debit) do
    GenServer.call(server,
      {:finish_tactical, player_id, encounter_id, outcome, report, cargo_debit})
  end

  @doc """
  Return the authenticated pilot's live strategic tactical contact.
  Never call from a client-supplied player ID; server callers must bind it
  to an authenticated SessionManager session. Manifest is authoritative.
  """
  def tactical_contact(server, player_id, encounter_id)
      when is_integer(player_id) and player_id > 0 and is_binary(encounter_id) do
    GenServer.call(server, {:tactical_contact, player_id, encounter_id})
  end

  @doc "Refresh the in-memory policy cache after a durable faction event."
  def set_faction_standing(server, player_id, faction_id, standing)
      when is_integer(player_id) and player_id > 0 and is_binary(faction_id) and
           is_integer(standing) and standing >= -100 and standing <= 100 do
    GenServer.call(server, {:set_faction_standing, player_id, faction_id, standing})
  end

  @doc "Hail an in-range contact; identity and position come from the server."
  @spec hail(GenServer.server(), pos_integer(), term()) :: {:ok, map()} | {:error, atom()}
  def hail(server, player_id, contact_id)
      when is_integer(player_id) and player_id > 0 do
    GenServer.call(server, {:hail, player_id, contact_id})
  end

  @doc """
  Hold the exact server-owned SOL location while a pilot is logged out.
  Unlike an NPC, an absent player's cruise is paused until reconnect.
  The hold is committed to PostgreSQL before acknowledging disconnect.
  """
  def pause_for_logout(server, player_id) when is_integer(player_id) and player_id > 0,
    do: GenServer.call(server, {:logout_pause, player_id})

  @doc "Resume the same voyage only after an authenticated world join succeeds."
  def resume_after_login(server, player_id) when is_integer(player_id) and player_id > 0,
    do: GenServer.call(server, {:login_resume, player_id})

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
      saved_voyages: %{},
      voyage_loader: Keyword.get(opts, :voyage_loader),
      voyage_saver: Keyword.get(opts, :voyage_saver),
      traffic: Keyword.get(opts, :traffic, Traffic.seed()),
      bases: Keyword.get(opts, :bases, SpaceBases.seed()),
      encountered: %{},
      # At most one pilot owns a given physical vessel during a tactical
      # encounter. Leases are bound to its current traffic voyage number.
      tactical_claims: %{},
      # Exact receipts permit retry when map cleanup fails after settlement.
      settled_tactical: %{},
      # Server-owned reputation fixtures until the faction ledger is connected.
      # Never supplied by Phoenix client payloads or exposed in public snapshots.
      pilot_reputations: Keyword.get(opts, :pilot_reputations, %{}),
      reputation_loader: Keyword.get(opts, :reputation_loader),
      # Isolated Navigation tests opt in; the actual world supervisor enables
      # procedural shared contacts so real departures are encounter-capable.
      procedural_contact_chance: Keyword.get(opts, :procedural_contact_chance, 0.0),
      # Global trade departures occur even with no connected player, on the
      # SOL clock. The destination selected by a pilot never schedules one.
      scheduled_trader_interval_ms: Keyword.get(opts, :scheduled_trader_interval_ms, 0),
      traffic_time_ms: 0,
      scheduled_trader_route_index: 0,
      next_contact_serial: 1,
      tick_ms: tick_ms,
      auto_tick?: Keyword.get(opts, :auto_tick, true),
      event_sink: Keyword.fetch!(opts, :event_sink)
    }
    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:logout_pause, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    if voyage.tactical_encounter do
      {:reply, {:error, :tactical_cleanup_pending}, state}
    else
      updated = Map.put(voyage, :logout_paused, true)
      case persist_connection_change(state, player_id, updated) do
        {:ok, state} -> {:reply, :ok, state}
        {:error, error} -> {:reply, {:error, error}, state}
      end
    end
  end

  def handle_call({:login_resume, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    updated = Map.put(voyage, :logout_paused, false)
    case persist_connection_change(state, player_id, updated) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:snapshot, player_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    {:reply, {:ok, public(voyage, state, player_id)}, state}
  end

  def handle_call({:tactical_contact, player_id, encounter_id}, _from, state) do
    {voyage, state} = ensure_player(state, player_id)

    response =
      case voyage.tactical_encounter do
        %{id: ^encounter_id, contact_id: contact_id,
          voyage_number: voyage_number, classification: classification} ->
          claim = Map.get(state.tactical_claims, contact_id)
          vessel = Map.get(state.traffic, contact_id)

          if claim == %{player_id: player_id, encounter_id: encounter_id,
                        voyage_number: voyage_number} and is_map(vessel) and
               vessel.voyage_number == voyage_number do
            {:ok, %{
              contact_id: contact_id, encounter_id: encounter_id,
              voyage_number: voyage_number, faction_id: vessel.faction_id,
              disposition: vessel.disposition, classification: classification,
              cargo: vessel.cargo, call_sign: vessel.call_sign,
              ship_class: vessel.ship_class
            }}
          else
            {:error, :tactical_claim_mismatch}
          end

        _ ->
          {:error, :no_tactical_encounter}
      end

    {:reply, response, state}
  end

  def handle_call({:set_faction_standing, player_id, faction_id, standing},
                  _from, state) do
    {voyage, state} = ensure_player(state, player_id)
    updated = Map.put(reputations_for(state, player_id), faction_id, standing)
    state = %{state | pilot_reputations:
      Map.put(state.pilot_reputations, player_id, updated)}
    broadcast(state, player_id, voyage)
    {:reply, :ok, state}
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
        updated =
          voyage
          |> Map.put(:pending_encounter, nil)
          |> Map.put(:encounter_clearance_until_ms,
            state.traffic_time_ms + @post_encounter_clearance_ms)
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
          faction_id: contact.faction_id,
          faction_name: Core.Factions.name(contact.faction_id) || contact.faction_id,
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

  def handle_call({:finish_tactical, player_id, encounter_id, outcome, report, cargo_debit},
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
                report.combat, outcome, cargo_debit)
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
                    voyage
                    |> Map.put(:tactical_encounter, nil)
                    |> Map.put(:pending_encounter, nil)
                    |> Map.put(:encounter_clearance_until_ms,
                      state.traffic_time_ms + @post_encounter_clearance_ms)
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
    state =
      if Map.has_key?(state.pilot_reputations, player_id) do
        state
      else
        persisted =
          case state.reputation_loader do
            fun when is_function(fun, 1) ->
              case fun.(player_id) do
                values when is_map(values) -> values
                _ -> %{}
              end

            _ ->
              %{}
          end

        %{state | pilot_reputations: Map.put(state.pilot_reputations,
          player_id, persisted)}
      end

    case Map.fetch(state.voyages, player_id) do
      {:ok, voyage} -> {voyage, state}
      :error ->
        case load_checkpoint(state, player_id) do
          {:ok, voyage} ->
            {voyage, %{state |
              voyages: Map.put(state.voyages, player_id, voyage),
              saved_voyages: Map.put(state.saved_voyages, player_id, voyage)
            }}
          :new ->
            voyage = idle("earth")
            {voyage, put_voyage(state, player_id, voyage)}
        end
    end
  end

  defp idle(location_id) do
    {:ok, position_km} = Sol.game_position_km(location_id)
    %{system_id: @system_id, status: :idle, logout_paused: false,
      location_id: location_id,
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

  @checkpoint_interval_ms 10_000
  @checkpoint_changed_fields [
    :status, :location_id, :origin_id, :destination_id, :arrival_origin_id,
    :voyage_number, :free_flight, :logout_paused
  ]

  defp load_checkpoint(%{voyage_loader: nil}, _player_id), do: :new
  defp load_checkpoint(%{voyage_loader: loader}, player_id) do
    case loader.(player_id) do
      nil -> :new
      data ->
        case Checkpoint.load(data) do
          {:ok, voyage} -> {:ok, voyage}
          {:error, reason} ->
            # Fail closed: a damaged checkpoint must not teleport an
            # established pilot to Earth on reconnect.
            raise "Invalid stored SOL location for pilot #{player_id}: #{inspect(reason)}"
        end
    end
  end

  # A logout must not appear successful if the DB checkpoint wasn't written.
  # Keep this separate from best-effort periodic checkpoints.
  defp persist_connection_change(state, player_id, updated) do
    if Map.get(state.voyages, player_id) == updated do
      {:ok, state}
    else
      result =
        case state.voyage_saver do
          nil -> :ok
          saver when is_function(saver, 2) ->
            try do
              saver.(player_id, Checkpoint.dump(updated))
            rescue
              error -> {:error, {:checkpoint_exception, Exception.message(error)}}
            end
        end

      case result do
        :ok ->
          {:ok, %{state |
            voyages: Map.put(state.voyages, player_id, updated),
            saved_voyages: Map.put(state.saved_voyages, player_id, updated)
          }}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp put_voyage(state, player_id, voyage) do
    state = %{state | voyages: Map.put(state.voyages, player_id, voyage)}
    saved = Map.get(state.saved_voyages, player_id)
    if is_function(state.voyage_saver, 2) and checkpoint_due?(saved, voyage) do
      # No SQL I/O in the 100 ms tactical physics tick. SOL travel writes
      # at a maximum of once per ten seconds, plus explicit state changes.
      try do
        case state.voyage_saver.(player_id, Checkpoint.dump(voyage)) do
          :ok -> %{state | saved_voyages: Map.put(state.saved_voyages, player_id, voyage)}
          {:error, reason} ->
            Logger.warning("SOL location checkpoint failed: #{inspect(reason)}")
            state
        end
      rescue
        error ->
          Logger.warning("SOL checkpoint unavailable: " <> Exception.message(error))
          state
      end
    else
      state
    end
  end

  defp checkpoint_due?(nil, _voyage), do: true
  defp checkpoint_due?(saved, voyage) do
    Enum.any?(@checkpoint_changed_fields, fn key ->
      Map.get(saved, key) != Map.get(voyage, key)
    end) or
      (voyage.status == :traveling and
        abs(voyage.elapsed_ms - saved.elapsed_ms) >= @checkpoint_interval_ms)
  end

  defp advance(state) do
    old_traffic = state.traffic
    old_bases = state.bases
    # Strategic traffic advances even if no pilot has ever joined.
    held = state.tactical_claims |> Map.keys() |> MapSet.new()
    {traffic, bases} =
      Traffic.advance_with_bases(state.traffic, state.tick_ms, state.bases, held)
    state = %{state | traffic: traffic, bases: bases}
    state = advance_scheduled_traders(state)

    Enum.reduce(state.voyages, state, fn
      {player_id, %{status: :traveling} = voyage}, current ->
        updated =
          if voyage.pending_encounter != nil or voyage.free_flight or
               Map.get(voyage, :logout_paused, false) do
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
        before_base = Map.get(old_bases, voyage.location_id)
        after_base = Map.get(current.bases, voyage.location_id)
        docking_changed? = before_base && after_base &&
          (before_base.berths != after_base.berths or
             before_base.docking_events != after_base.docking_events)
        # Idle pilots get changes to their *local* dock even without passing
        # SOL traffic. Refinery stock production alone does not spam sockets.
        if before != [] or after_contacts != [] or docking_changed? do
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
      # Distinct from all planetary forward refineries. Fixed by the server;
      # routes use the existing, validated free-waypoint format.
      starbases: GreenStarbase.catalog(),
      green_starbase_nearby: GreenStarbase.nearby?(voyage),
      # Only the local base is included, avoiding nine facility records on
      # every tick and keeping remote refinery inventories server-private.
      space_base: if(voyage.status == :idle and is_binary(voyage.location_id),
        do: SpaceBases.public(state.bases, voyage.location_id), else: nil),
      traffic_pressure: TradeLanes.pressure(voyage.position_km),
      traffic_band: TradeLanes.band(voyage.position_km),
      # While a decision or fight is active, the *held* physical contact is
      # the only encounter. A newer nearest contact must not overwrite its
      # displayed identity or faction during combat.
      encounter: cond do
        is_map(voyage.pending_encounter) -> voyage.pending_encounter
        is_map(voyage.tactical_encounter) -> nil
        state.traffic_time_ms < Map.get(voyage, :encounter_clearance_until_ms, 0) -> nil
        true -> EncounterDirector.evaluate(traffic, voyage, reputations_for(state, player_id))
      end,
      cruise_paused: voyage.pending_encounter != nil or voyage.free_flight or
        Map.get(voyage, :logout_paused, false),
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

  # World-owned shipping timetable. A trader is a single independently
  # moving vessel for every pilot, not a per-encounter spawn. Only server
  # config can enable the schedule; no route is chosen by a client click.
  defp advance_scheduled_traders(state) do
    interval = state.scheduled_trader_interval_ms
    elapsed = state.traffic_time_ms + state.tick_ms
    state = %{state | traffic_time_ms: elapsed}

    if is_integer(interval) and interval > 0 and
         div(elapsed, interval) > div(elapsed - state.tick_ms, interval) do
      routes = TradeLanes.departures()
      index = rem(state.scheduled_trader_route_index, length(routes))
      {from_id, to_id} = Enum.at(routes, index)
      serial = state.next_contact_serial

      result = Traffic.launch_scheduled_trader(
        state.traffic, from_id, to_id, serial)

      # Advance the timetable even when fleet capacity is full. Skipped
      # departures are not recreated when a particular player arrives.
      state = %{state | next_contact_serial: serial + 1,
        scheduled_trader_route_index: state.scheduled_trader_route_index + 1}

      case result do
        {:ok, updated} ->
          vessel = Map.fetch!(updated, "traffic:sol:cruise-" <> Integer.to_string(serial))
          {bases, loaded} = SpaceBases.dispatch(state.bases, vessel)
          %{state | traffic: Map.put(updated, loaded.id, loaded), bases: bases}

        {:error, _} -> state
      end
    else
      state
    end
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
          vessel = Map.fetch!(traffic, "traffic:sol:cruise-" <> Integer.to_string(serial))
          {bases, loaded} = SpaceBases.dispatch(state.bases, vessel)
          %{state | traffic: Map.put(traffic, loaded.id, loaded), bases: bases,
            next_contact_serial: serial + 1}

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
  defp announce_encounter(state, _player_id, %{logout_paused: true}), do: state
  defp announce_encounter(state, _player_id, %{free_flight: true}), do: state

  defp announce_encounter(state, _player_id,
         %{tactical_encounter: tactical}) when not is_nil(tactical), do: state

  defp announce_encounter(state, player_id, voyage)
       when is_map(voyage) do
    if state.traffic_time_ms <
         Map.get(voyage, :encounter_clearance_until_ms, 0) do
      state
    else
      announce_encounter_ready(state, player_id, voyage)
    end
  end

  defp announce_encounter_ready(state, _player_id, %{pending_encounter: pending})
       when not is_nil(pending), do: state

  defp announce_encounter_ready(state, player_id, voyage) do
    case EncounterDirector.evaluate(state.traffic, voyage, reputations_for(state, player_id)) do
      nil -> state
      encounter ->
        seen = Map.get(state.encountered, player_id, MapSet.new())
        if MapSet.member?(seen, encounter.id) do
          state
        else
          state = put_voyage(state, player_id, %{voyage | pending_encounter: encounter})
          state = %{state | encountered: Map.put(state.encountered, player_id,
            MapSet.put(seen, encounter.id))}
          EventSink.dispatch(state.event_sink, "sol", :solar_encounter_started, %{
            player_id: player_id, encounter: encounter
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
