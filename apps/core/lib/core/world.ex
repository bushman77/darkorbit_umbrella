defmodule Core.World do
  @moduledoc """
  Public session and command API for the authoritative world simulation.

  Clients provide movement intentions only. Positions are read from map-owned
  state and advance exclusively on simulation ticks.
  """

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
           {:ok, _entity} <- join_or_close(registry, sessions, session, stats) do
        {:ok, session}
      end
    else
      {:error, :map_not_found}
    end
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

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.move(registry, session.map_id, session.id, session.entity_id, destination)
    end
  end

  @doc "Submit a bounded series of waypoints for server-owned autopilot."
  @spec plot_course(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def plot_course(session_id, waypoints, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.plot_course(registry, session.map_id, session.id, session.entity_id, waypoints)
    end
  end

  @doc "Cancel any course without trusting client-supplied position."
  @spec stop_navigation(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def stop_navigation(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.stop_navigation(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @doc "Apply authenticated signed throttle and rotational flight commands."
  @spec flight_controls(pos_integer(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def flight_controls(session_id, input, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.flight_controls(registry, session.map_id, session.id, session.entity_id, input)
    end
  end

  @spec select_target(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def select_target(session_id, target_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
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

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.clear_target(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec engage_combat(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def engage_combat(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.engage_combat(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec disengage_combat(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def disengage_combat(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.disengage_combat(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec toggle_laser_fire(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def toggle_laser_fire(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.toggle_laser_fire(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec activate_action(pos_integer(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def activate_action(session_id, slot, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.activate_action(registry, session.map_id, session.id, session.entity_id, slot)
    end
  end

  @doc "Fire the ready laser along the authenticated ship's current nose."
  @spec fire_ready_weapon(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def fire_ready_weapon(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
      MapServer.fire_ready_weapon(registry, session.map_id, session.id, session.entity_id)
    end
  end

  @spec attack(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def attack(session_id, opts \\ []) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)

    with {:ok, session} <- fetch_session(sessions, session_id) do
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

  defp join_or_close(registry, sessions, session, stats) do
    case MapServer.join(registry, session.map_id, session, stats) do
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
