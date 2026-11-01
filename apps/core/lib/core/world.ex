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
