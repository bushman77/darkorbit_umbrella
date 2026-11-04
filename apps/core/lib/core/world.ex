defmodule Core.World do
  @moduledoc """
  Public session and command API for the authoritative world simulation.

  Clients provide movement intentions only. Positions are read from map-owned
  state and advance exclusively on simulation ticks.
  """

  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.World.MapDefinition
  alias Core.World.MapServer
  alias Core.World.Session
  alias Core.World.SessionManager

  @spec connect(term(), map(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def connect(player_id, stats, opts \\ []) do
    map_id = Keyword.get(opts, :map_id, MapDefinition.starting_map_id())
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    if MapServer.available?(registry, map_id) do
      with {:ok, session} <- SessionManager.open(sessions, player_id, map_id),
           {:ok, _entity} <- join_or_close(registry, sessions, session, stats,
             Keyword.get(opts, :entry)) do
        {:ok, session}
      end
    else
      {:error, :map_not_found}
    end
  end

  @doc "Server-owned SOL travel status. Session identity is verified internally."
  @spec solar_snapshot(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def solar_snapshot(session_id, opts \\ []) do
    with {:ok, session} <- fetch_session(Keyword.get(opts, :sessions, SessionManager), session_id) do
      SolarNavigation.snapshot(solar_navigation_server(opts), session.player_id)
    end
  end

  @spec solar_set_course(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def solar_set_course(session_id, destination_id, opts \\ []) do
    with {:ok, session} <- fetch_session(Keyword.get(opts, :sessions, SessionManager), session_id),
         {:ok, navigation} <-
           SolarNavigation.set_course(solar_navigation_server(opts), session.player_id, destination_id) do
      # Solar cruise is a separate propulsion regime. Clear any local course
      # and weapon lock once the server accepts the interplanetary course;
      # the pilot cannot fly or fight simultaneously in both regimes.
      registry = Keyword.get(opts, :registry, Core.World.Registry)
      _ = MapServer.stop_navigation(registry, session.map_id, session.id, session.entity_id)
      _ = MapServer.disengage_combat(registry, session.map_id, session.id, session.entity_id)
      {:ok, navigation}
    end
  end

  @spec solar_cancel_course(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def solar_cancel_course(session_id, opts \\ []) do
    with {:ok, session} <- fetch_session(Keyword.get(opts, :sessions, SessionManager), session_id) do
      SolarNavigation.cancel_course(solar_navigation_server(opts), session.player_id)
    end
  end

  @doc "Authenticated, in-range communications with a strategic SOL contact."
  @spec solar_hail(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def solar_hail(session_id, contact_id, opts \\ []) do
    with {:ok, session} <- fetch_session(Keyword.get(opts, :sessions, SessionManager), session_id) do
      SolarNavigation.hail(solar_navigation_server(opts), session.player_id, contact_id)
    end
  end

  @doc "Resolve a server-held encounter using the authenticated pilot session."
  @spec solar_resolve_encounter(pos_integer(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def solar_resolve_encounter(session_id, encounter_id, choice, opts \\ []) do
    with {:ok, session} <- fetch_session(Keyword.get(opts, :sessions, SessionManager), session_id) do
      SolarNavigation.resolve_encounter(
        solar_navigation_server(opts), session.player_id, encounter_id, choice)
    end
  end

  @doc "Enter the authenticated pilot's held hostile encounter in local 3D combat."
  @spec solar_enter_tactical(pos_integer(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def solar_enter_tactical(session_id, encounter_id, opts \\ []) do
    sessions = Keyword.get(opts, :sessions, SessionManager)
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    server = solar_navigation_server(opts)

    with {:ok, session} <- fetch_session(sessions, session_id),
         {:ok, navigation} <-
           SolarNavigation.enter_tactical(server, session.player_id, encounter_id) do
      aggressive? = navigation.tactical_encounter.classification != :neutral_flyby

      case MapServer.start_solar_tactical(registry, session.map_id, session.id,
             session.entity_id, encounter_id, navigation.tactical_encounter.call_sign,
             navigation.tactical_encounter.ship_class, aggressive?,
             navigation.tactical_encounter.course) do
        {:ok, enemy} ->
          {:ok, %{navigation: navigation, enemy: enemy}}

        {:error, reason} ->
          # Preserve the original modal if map combat could not be created.
          _ = SolarNavigation.finish_tactical(
            server, session.player_id, encounter_id, :rollback)
          {:error, reason}
      end
    end
  end

  @doc "Map-server verified victory or retreat, then resume the held SOL voyage."
  @spec solar_finish_tactical(pos_integer(), String.t(), atom(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def solar_finish_tactical(session_id, encounter_id, outcome, opts \\ [])
      when outcome in [:victory, :retreat, :defeat, :surrender] do
    sessions = Keyword.get(opts, :sessions, SessionManager)
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    server = solar_navigation_server(opts)

    with {:ok, session} <- fetch_session(sessions, session_id),
         {:ok, %{tactical_encounter: %{id: ^encounter_id}}} <-
           SolarNavigation.snapshot(server, session.player_id),
         :ok <- MapServer.finish_solar_tactical(registry, session.map_id,
           session.id, session.entity_id, encounter_id, outcome) do
      SolarNavigation.finish_tactical(server, session.player_id, encounter_id, outcome)
    else
      {:ok, %{tactical_encounter: nil}} -> {:error, :no_tactical_encounter}
      {:ok, _} -> {:error, :encounter_mismatch}
      error -> error
    end
  end

  defp solar_navigation_server(opts) do
    Keyword.get(opts, :solar_navigation_server,
      Module.concat(Keyword.get(opts, :sessions, SessionManager), SolarNavigation))
  end

  @doc "Server-only encounter cleanup, not a client command."
  @spec clear_encounters(keyword()) :: :ok | {:error, term()}
  def clear_encounters(opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    map_id = Keyword.get(opts, :map_id, MapDefinition.starting_map_id())
    MapServer.clear_encounters(registry, map_id)
  end

  @doc "Server-authorized encounter entry; not a client command."
  @spec start_encounter(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_encounter(npc_type_id, opts \\ []) when is_binary(npc_type_id) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    map_id = Keyword.get(opts, :map_id, MapDefinition.starting_map_id())
    MapServer.start_encounter(registry, map_id, npc_type_id)
  end

  @spec disconnect(pos_integer(), keyword()) :: :ok | {:error, term()}
  def disconnect(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- MapServer.leave(registry, session.map_id, session.id, session.entity_id),
         {:ok, _session} <- SessionManager.close(sessions, session.id) do
      :ok
    end
  end

  @spec move(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def move(session_id, destination, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.move(registry, session.map_id, session.id, session.entity_id, destination)
    end
  end

  @doc "Submit a bounded series of waypoints for server-owned autopilot."
  @spec plot_course(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def plot_course(session_id, waypoints, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.plot_course(registry, session.map_id, session.id, session.entity_id, waypoints)
    end
  end

  @doc "Cancel any course without trusting client-supplied position."
  @spec stop_navigation(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def stop_navigation(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.stop_navigation(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @doc "Apply authenticated signed throttle and rotational flight commands."
  @spec flight_controls(pos_integer(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def flight_controls(session_id, input, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.flight_controls(registry, session.map_id, session.id, session.entity_id, input)
    end
  end

  @spec select_target(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def select_target(session_id, target_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.select_target(
        registry,
        session.map_id,
        session.id,
        session.entity_id,
        target_id
      )
    end
  end

  @spec clear_target(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def clear_target(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.clear_target(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec engage_combat(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def engage_combat(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.engage_combat(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec disengage_combat(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def disengage_combat(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.disengage_combat(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec toggle_laser_fire(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def toggle_laser_fire(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.toggle_laser_fire(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec activate_action(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def activate_action(session_id, slot, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.activate_action(registry, session.map_id, session.id, session.entity_id, slot)
    end
  end

  @doc "Fire the ready laser along the authenticated ship's current nose."
  @spec fire_ready_weapon(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def fire_ready_weapon(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.fire_ready_weapon(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec attack(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def attack(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id),
         :ok <- require_conventional(session, opts) do
      MapServer.attack(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec snapshot(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def snapshot(map_id \\ MapDefinition.starting_map_id(), opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    MapServer.snapshot(registry, map_id)
  end

  @spec tick(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def tick(map_id \\ MapDefinition.starting_map_id(), opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    MapServer.tick(registry, map_id)
  end

  # Enforce the propulsion boundary at the authoritative game API, not
  # solely in browser controls or Phoenix. Test worlds also support
  # symbolic player IDs for deterministic combat fixtures.
  defp require_conventional(%Session{player_id: player_id}, opts)
       when is_integer(player_id) and player_id > 0 do
    case SolarNavigation.snapshot(solar_navigation_server(opts), player_id) do
      {:ok, %{status: :traveling, tactical_encounter: %{}}} -> :ok
      {:ok, %{status: :traveling}} -> {:error, :interplanetary_cruise_active}
      {:ok, _navigation} -> :ok
      error -> error
    end
  end

  defp require_conventional(_session, _opts), do: :ok

  defp join_or_close(registry, sessions, session, stats, entry) do
    case MapServer.join(registry, session.map_id, session, stats, entry) do
      {:ok, entity} ->
        {:ok, entity}

      {:error, reason} ->
        SessionManager.close(sessions, session.id)
        {:error, reason}
    end
  end

  defp fetch_session(sessions, session_id) do
    case SessionManager.fetch(sessions, session_id) do
      {:ok, session} -> {:ok, session}
      :error -> {:error, :session_not_found}
    end
  end
end
