defmodule Darkorbit.World do
  @moduledoc """
  Persistence-aware entry point to the authoritative world simulation.

  Connecting snapshots the active ship's derived combat and movement stats
  into the runtime entity. Subsequent simulation remains independent of
  PostgreSQL and Phoenix.
  """

  alias Core.World, as: Simulation
  alias Core.World.MapServer
  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.Universe.OrbitalEntry
  alias Core.Universe.FreeFlightRegion
  alias Core.World.SessionManager
  alias Core.World.MapDefinition
  alias Darkorbit.Accounts
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet
  alias Darkorbit.Loadouts
  alias Darkorbit.ShipStats
  alias Darkorbit.ShipCondition
  alias Darkorbit.Piracy
  alias Darkorbit.PilotLocation
  alias Darkorbit.World.PubSub

  @legacy_test_earth_sector Application.compile_env(:darkorbit, :legacy_test_earth_sector, false)

  @doc "Resolve an authenticated pilot's current planetary map and arrival pose."
  @spec region_for_player(pos_integer()) :: {:ok, map()} | {:error, term()}
  def region_for_player(user_id) when is_integer(user_id) and user_id > 0 do
    server = Module.concat(SessionManager, SolarNavigation)

    with {:ok, navigation} <- SolarNavigation.snapshot(server, user_id) do
      # Only the test environment runs the isolated legacy Sector 1-1
      # channel fixtures. In production EVERY planet (including Earth)
      # receives the same physical orbital region and collision mechanics.
      if navigation.status == :traveling or is_nil(navigation.location_id) do
        with :ok <- FreeFlightRegion.ensure_started(user_id) do
          FreeFlightRegion.entry(user_id, navigation)
        end
      else
        if @legacy_test_earth_sector and navigation.location_id == "earth" and
             navigation.arrival_origin_id == nil do
          {:ok, %{
            map_id: "1-1",
            position: MapDefinition.starting_map().spawn,
            attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
          }}
        else
          OrbitalEntry.entry(
            navigation.arrival_origin_id, navigation.location_id,
            user_id, navigation.voyage_number
          )
        end
      end
    end
  end

  @doc "Persisted choice of active configuration, defaulting to one for old pilots."
  def active_configuration(user_id) when is_integer(user_id) do
    case Accounts.get_player_account!(user_id) do
      %PlayerAccount{data: %{"active_configuration" => 2}} -> 2
      _ -> 1
    end
  end

  @spec connect(pos_integer(), 1 | 2, keyword()) ::
          {:ok, Core.World.Session.t()} | {:error, term()}
  def connect(user_id, config_no \\ 1, opts \\ []) do
    with :ok <- recover_prepared_departure(user_id),
         {:ok, player_ship} <- Fleet.get_active_ship(user_id),
         {:ok, stats} <- ShipStats.calculate(user_id, player_ship.id, config_no),
         {:ok, condition} <-
           ShipCondition.load_or_initialize(user_id, player_ship.id, stats),
         {:ok, entry} <- region_for_player(user_id),
         {:ok, navigation} <- SolarNavigation.snapshot(
           Module.concat(SessionManager, SolarNavigation), user_id) do
      # While automated cruise is active, the saved strategic position is
      # authoritative; a previous manual cockpit pose must not override it.
      entry =
        if navigation.status == :traveling and not navigation.free_flight do
          entry
        else
          PilotLocation.restore_entry(
            user_id, player_ship.id, entry, navigation.voyage_number)
        end
      requested_map = Keyword.get(opts, :map_id, entry.map_id)

      if requested_map == entry.map_id do
        case Simulation.connect(user_id, stats, map_id: requested_map, entry: entry,
               ship_instance_id: player_ship.id, combat_condition: condition) do
          {:ok, _session} = success ->
            # Refresh the policy cache from durable faction standings on every
            # authenticated reconnection. No DB queries run in the map tick.
            server = Module.concat(SessionManager, SolarNavigation)
            Enum.each(Piracy.reputations(user_id), fn {faction, standing} ->
              :ok = SolarNavigation.set_faction_standing(
                server, user_id, faction, standing)
            end)
            session_id = elem(success, 1).id
            with :ok <- maybe_restore_docked(session_id, entry),
                 :ok <- maybe_restore_station_position(session_id, entry),
                 :ok <- SolarNavigation.resume_after_login(server, user_id) do
              success
            else
              {:error, reason} ->
                _ = Simulation.disconnect(session_id)
                {:error, {:location_resume_failed, reason}}
            end

          error ->
            error
        end
      else
        {:error, :wrong_orbital_region}
      end
    end
  end

  defp maybe_restore_docked(session_id, %{docked: true}),
    do: Simulation.restore_dock(session_id)
  defp maybe_restore_docked(_session_id, _entry), do: :ok

  defp maybe_restore_station_position(session_id,
       %{docked: true, station_position: position}),
    do: Simulation.restore_station_position(session_id, position)
  defp maybe_restore_station_position(_session_id, _entry), do: :ok

  @doc "Request the Green Starbase berth; save its state before acknowledging."
  def dock(session_id) do
    case Simulation.dock(session_id) do
      {:ok, status} ->
        case checkpoint_location(session_id) do
          :ok -> {:ok, status}
          {:error, reason} ->
            _ = Simulation.launch(session_id)
            {:error, {:docking_checkpoint_failed, reason}}
        end
      error -> error
    end
  end

  @doc "Launch an authenticated parked ship without rebuilding its combat state."
  def launch(session_id) do
    case Simulation.launch(session_id) do
      {:ok, _status} = result ->
        case checkpoint_location(session_id) do
          :ok -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Green Starbase launch checkpoint: #{inspect(reason)}")
        end
        result
      error -> error
    end
  end

  defdelegate docking_status(session_id), to: Simulation

  @doc """
  Accept bounded station-walking axes for the authenticated docked session.
  The map process owns the avatar coordinates and collision; only the desktop
  pilot's world channel can invoke this API.
  """
  def station_walk(session_id, input) when is_map(input),
    do: Simulation.station_walk(session_id, input)

  @doc "Apply a bounded station heading change, not a client-supplied pose."
  def station_look(session_id, input) when is_map(input),
    do: Simulation.station_look(session_id, input)

  @doc "Talk to a nearby station attendant; no client-supplied location."
  def station_talk(session_id, attendant_id, topic)
      when is_binary(attendant_id) and is_binary(topic),
      do: Simulation.station_talk(session_id, attendant_id, topic)

  @doc "Settle any live combat and persist map-owned damage before disconnecting."
  def disconnect(session_id) do
    with :ok <- settle_on_disconnect(session_id),
         {:ok, %{player_id: player_id, ship_instance_id: ship_id,
                  combat: condition} = report} <- Simulation.prepare_disconnect(session_id),
         :ok <- ShipCondition.save_verified(player_id, ship_id, condition),
         :ok <- persist_verified_pose(session_id, report),
         :ok <- SolarNavigation.pause_for_logout(
           Module.concat(SessionManager, SolarNavigation), player_id) do
      Simulation.disconnect(session_id)
    end
  end

  @doc "Periodic server-only pose checkpoint, independent of client input."
  def checkpoint_location(session_id) do
    with {:ok, report} <- Simulation.ship_condition(session_id) do
      persist_verified_pose(session_id, report)
    end
  end

  defp persist_verified_pose(session_id, report) do
    with {:ok, session} <- SessionManager.fetch(SessionManager, session_id),
         {:ok, navigation} <- SolarNavigation.snapshot(
           Module.concat(SessionManager, SolarNavigation), session.player_id) do
      PilotLocation.save_pose(session.player_id, session.map_id, navigation, report)
    else
      :error -> {:error, :session_not_found}
      {:error, _} = error -> error
    end
  end

  defp recover_prepared_departure(player_id) do
    case SessionManager.fetch_player(SessionManager, player_id) do
      {:ok, session} ->
        with :ok <- recover_tactical_cleanup(session.id) do
          # Tactical recovery may have already closed the previous session.
          case SessionManager.fetch_player(SessionManager, player_id) do
            :error ->
              :ok

            {:ok, remaining} ->
              case Simulation.pending_disconnect?(remaining.id) do
                {:ok, true} -> disconnect(remaining.id)
                {:ok, false} -> :ok
                error -> error
              end
          end
        end

      :error ->
        :ok
    end
  end

  defp recover_tactical_cleanup(session_id) do
    case Simulation.pending_tactical_cleanup(session_id) do
      {:ok, {encounter_id, outcome}} ->
        with {:ok, _} <- solar_finish_tactical(session_id, encounter_id, outcome) do
          # This old session was already frozen mid-settlement. Release it
          # before admitting another authenticated connection for its pilot.
          disconnect(session_id)
        end

      {:ok, nil} ->
        :ok

      error ->
        error
    end
  end

  defp settle_on_disconnect(session_id) do
    case Simulation.solar_snapshot(session_id) do
      {:ok, %{tactical_encounter: %{id: encounter_id}}} ->
        with {:ok, outcome} <- Simulation.solar_tactical_outcome(session_id, encounter_id),
             {:ok, _} <- solar_finish_tactical(session_id, encounter_id, outcome) do
          :ok
        end

      {:ok, _} ->
        case Simulation.pending_tactical_cleanup(session_id) do
          {:ok, {encounter_id, outcome}} ->
            with {:ok, _} <- solar_finish_tactical(session_id, encounter_id, outcome) do
              :ok
            end

          {:ok, nil} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Authenticated recovery after verified ship destruction. Retain the owned
  ship/loadout, settle a held tactical encounter, restore SOL to Earth, and
  release the old world session before the client rejoins.
  """
  def respawn(session_id) do
    server = Module.concat(SessionManager, SolarNavigation)

    with {:ok, session} <- SessionManager.fetch(SessionManager, session_id),
         {:ok, report} <- Simulation.ship_condition(session_id),
         :ok <- require_destroyed_for_respawn(report),
         {:ok, stats} <- ShipStats.calculate(session.player_id,
           session.ship_instance_id, active_configuration(session.player_id)),
         :ok <- settle_respawn_encounter(session_id),
         :ok <- ShipCondition.save_verified(session.player_id,
           session.ship_instance_id, report.combat),
         {:ok, _navigation} <- SolarNavigation.respawn_at_earth(server, session.player_id),
         :ok <- Simulation.disconnect(session_id),
         {:ok, _restored} <- ShipCondition.repair_for_respawn(
           session.player_id, session.ship_instance_id, stats),
         {:ok, region} <- region_for_player(session.player_id) do
      {:ok, region}
    else
      :error -> {:error, :session_not_found}
      {:error, _} = error -> error
    end
  end

  defp require_destroyed_for_respawn(%{combat: %{status: :destroyed, hull: 0}}),
    do: :ok
  defp require_destroyed_for_respawn(_report), do: {:error, :ship_not_destroyed}

  defp settle_respawn_encounter(session_id) do
    case Simulation.solar_snapshot(session_id) do
      {:ok, %{tactical_encounter: %{id: id}}} ->
        case solar_finish_tactical(session_id, id, :defeat) do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end

      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defdelegate move(session_id, destination), to: Simulation
  defdelegate plot_course(session_id, waypoints), to: Simulation
  defdelegate stop_navigation(session_id), to: Simulation
  defdelegate solar_snapshot(session_id), to: Simulation
  defdelegate solar_set_course(session_id, destination_id), to: Simulation
  defdelegate solar_cancel_course(session_id), to: Simulation
  defdelegate solar_enter_free_flight(session_id), to: Simulation
  defdelegate solar_resume_cruise(session_id), to: Simulation
  defdelegate solar_hail(session_id, contact_id), to: Simulation
  defdelegate solar_resolve_encounter(session_id, encounter_id, choice), to: Simulation
  defdelegate solar_enter_tactical(session_id, encounter_id), to: Simulation
  @doc """
  Settle the map-verified encounter and optionally seize cargo. Cargo cannot
  be claimed from a browser-supplied manifest. The DB receipt is idempotent.
  """
  def solar_finish_tactical(session_id, encounter_id, outcome, opts \\ []) do
    server = Module.concat(SessionManager, SolarNavigation)
    claim_cargo? = Keyword.get(opts, :claim_cargo, false) == true

    Simulation.solar_finish_tactical(session_id, encounter_id, outcome,
      persist_player_condition: fn %{player_id: player_id,
                                     ship_instance_id: ship_id, combat: combat} ->
        ShipCondition.save_verified(player_id, ship_id, combat)
      end,
      persist_tactical_effect: fn player_id, id, verified_outcome, npc_report ->
        if verified_outcome == :surrender do
          # A DB receipt can outlive the temporary SOL tactical lease if map
          # cleanup failed. Replay its exact debit instead of trying to mint
          # cargo again, including if the player chooses Release on retry.
          receipt =
            case Piracy.claim_receipt(player_id, id) do
              {:ok, previous} -> {:ok, previous}

              {:error, :claim_not_found} when claim_cargo? ->
                with {:ok, source} <- SolarNavigation.tactical_contact(server, player_id, id),
                     true <- source.contact_id == npc_report.contact_id and
                       source.voyage_number == npc_report.voyage_number and
                       source.encounter_id == npc_report.encounter_id do
                  Piracy.seize_surrender(player_id, source)
                else
                  false -> {:error, :tactical_claim_mismatch}
                  error -> error
                end

              {:error, :claim_not_found} ->
                {:ok, %{}}
            end

          with {:ok, effect} <- receipt do
            if Map.has_key?(effect, :faction_id) do
              with :ok <- SolarNavigation.set_faction_standing(
                server, player_id, effect.faction_id, effect.standing) do
                {:ok, effect}
              end
            else
              {:ok, effect}
            end
          end
        else
          {:ok, %{}}
        end
      end)
  end

  @doc "Read-only receipt for an authenticated pilot after cargo seizure."
  def cargo_claim_receipt(player_id, encounter_id) do
    Piracy.claim_receipt(player_id, encounter_id)
  end

  @doc """
  Receive a server-produced hit event, verify its local target matches the
  pilot's claimed strategic vessel, then assess a one-time civilian attack hit.
  Never accept this event type directly from a Phoenix client.
  """
  def record_tactical_hit(session_id, %{attacker_id: attacker_id,
                                         target_id: target_id, hit: true}) do
    server = Module.concat(SessionManager, SolarNavigation)

    with {:ok, session} <- SessionManager.fetch(SessionManager, session_id),
         true <- session.player_id == attacker_id,
         {:ok, navigation} <- Simulation.solar_snapshot(session_id),
         %{id: encounter_id} <- navigation.tactical_encounter,
         {:ok, source} <- SolarNavigation.tactical_contact(
           server, session.player_id, encounter_id),
         {:ok, proof} <- MapServer.tactical_target_identity(
           Core.World.Registry, session.map_id, session.id, session.entity_id, target_id),
         true <- proof == %{contact_id: source.contact_id,
                            voyage_number: source.voyage_number,
                            encounter_id: source.encounter_id},
         {:ok, consequence} <- Piracy.record_attack(session.player_id, source),
         :ok <- SolarNavigation.set_faction_standing(server, session.player_id,
           consequence.faction_id, consequence.standing) do
      {:ok, consequence}
    else
      false -> {:error, :unrelated_attack}
      nil -> {:error, :no_tactical_target}
      :error -> {:error, :unknown_session}
      {:error, _} = error -> error
      _ -> {:error, :unrelated_attack}
    end
  end

  def record_tactical_hit(_session_id, _payload), do: {:error, :unrelated_attack}
  defdelegate flight_controls(session_id, input), to: Simulation
  defdelegate select_target(session_id, target_id), to: Simulation
  defdelegate clear_target(session_id), to: Simulation
  defdelegate engage_combat(session_id), to: Simulation
  defdelegate disengage_combat(session_id), to: Simulation
  defdelegate toggle_laser_fire(session_id), to: Simulation
  defdelegate activate_action(session_id, slot), to: Simulation
  defdelegate attack(session_id), to: Simulation
  defdelegate fire_ready_weapon(session_id), to: Simulation

  @spec action_hotbar() :: [Core.Combat.ActionCatalog.slot()]
  def action_hotbar, do: Core.Combat.ActionCatalog.hotbar()

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(map_id \\ MapDefinition.starting_map_id()), do: Simulation.snapshot(map_id)

  @spec tick(String.t()) :: {:ok, map()} | {:error, term()}
  def tick(map_id \\ MapDefinition.starting_map_id()), do: Simulation.tick(map_id)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(map_id \\ MapDefinition.starting_map_id()) do
    Phoenix.PubSub.subscribe(Darkorbit.PubSub, PubSub.topic(map_id))
  end

  @spec player_status(pos_integer(), 1 | 2) :: {:ok, map()} | {:error, term()}
  def player_status(user_id, config_no \\ 1)
      when is_integer(user_id) and config_no in [1, 2] do
    with %PlayerAccount{} = account <- Accounts.get_player_account!(user_id),
         {:ok, player_ship} <- Fleet.get_active_ship(user_id),
         %{} = loadout <- Loadouts.get_loadout(player_ship.id, config_no),
         {:ok, stats} <- ShipStats.calculate(user_id, player_ship.id, config_no),
         {:ok, ship} <- Core.Ships.Catalog.fetch(player_ship.ship_id) do
      {:ok,
       %{
         pilot: summarize_player(account),
         ship: %{id: ship.id, name: ship.name},
         stats: Map.from_struct(stats),
         configuration: %{
           number: config_no,
           lasers: equipment_slots(loadout.lasers),
           generators: equipment_slots(loadout.generators),
           drones: equipment_slots(loadout.drones)
         }
       }}
    else
      nil -> {:error, :loadout_not_found}
      error -> error
    end
  rescue
    Ecto.NoResultsError -> {:error, :player_not_found}
  end

  @spec player_summaries([pos_integer()]) :: %{optional(pos_integer()) => map()}
  def player_summaries(player_ids) when is_list(player_ids) do
    player_ids
    |> Accounts.get_player_accounts()
    |> Map.new(fn account -> {account.id, summarize_player(account)} end)
  end

  @spec player_summary(pos_integer()) :: map() | nil
  def player_summary(player_id) when is_integer(player_id) do
    case Accounts.get_player_accounts([player_id]) do
      [account] -> summarize_player(account)
      [] -> nil
    end
  end

  defp summarize_player(%PlayerAccount{} = account) do
    %{
      id: account.id,
      pilot_name: account.pilot_name,
      username: account.username,
      faction_id: account.faction_id
    }
  end

  defp equipment_slots(equipment) when is_map(equipment) do
    ["ship", "drones", "slots"]
    |> Enum.flat_map(fn location ->
      equipment
      |> Map.get(location, [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn
        {nil, _slot} -> []
        {item_id, slot} -> [equipment_slot(item_id, location, slot)]
      end)
    end)
  end

  defp equipment_slots(_slots), do: []

  defp equipment_slot(item_id, location, slot) do
    case Core.Equipment.Catalog.fetch(item_id) do
      {:ok, item} ->
        %{
          location: location,
          slot: slot,
          id: item.id,
          name: item.name,
          category: item.category
        }

      :error ->
        %{location: location, slot: slot, id: item_id, name: item_id, category: :unknown}
    end
  end
end
