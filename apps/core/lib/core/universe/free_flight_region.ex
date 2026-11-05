defmodule Core.Universe.FreeFlightRegion do
  @moduledoc """
  Private, server-owned SOL deep-space flight region for the first free-flight slice.

  This first stage uses one local region per pilot rather than placing
  unrelated ships into a false shared battlefield. Navigation retains the
  authoritative SOL position; local cockpit units are independent.
  """

  alias Core.World.{MapDefinition, MapServer, NoopEventSink, Position, SessionManager}

  @size 24_000

  @spec map_id(pos_integer()) :: String.t()
  def map_id(player_id) when is_integer(player_id) and player_id > 0,
    do: "sol:free_#{player_id}"

  @spec definition(pos_integer()) :: MapDefinition.t()
  def definition(player_id) do
    %MapDefinition{
      id: map_id(player_id),
      name: "SOL Deep Space",
      width: @size, height: @size,
      altitude_min: -12_000, altitude_max: 12_000,
      spawn: %Position{x: 12_000.0, y: 12_000.0, z: 0.0}
    }
  end

  @doc "Face the SOL route when entering a deep-space cockpit region."
  @spec entry(pos_integer(), map()) :: {:ok, map()} | {:error, atom()}
  def entry(player_id,
        %{status: :traveling, origin_position_km: from,
          destination_position_km: to})
      when is_integer(player_id) and player_id > 0 and is_map(from) and is_map(to) do
    dx = to.x - from.x
    dy = to.y - from.y
    if dx * dx + dy * dy <= 0.0 do
      {:error, :invalid_flight_course}
    else
      {:ok, %{
        map_id: map_id(player_id),
        position: definition(player_id).spawn,
        attitude: %{yaw: :math.atan2(-dx, dy), pitch: 0.0, roll: 0.0}
      }}
    end
  end

  def entry(player_id, %{status: :idle, location_id: nil, position_km: position})
      when is_integer(player_id) and player_id > 0 and is_map(position) do
    {:ok, %{map_id: map_id(player_id), position: definition(player_id).spawn,
      attitude: %{yaw: 0.0, pitch: 0.0, roll: 0.0}}}
  end

  def entry(_player_id, _navigation), do: {:error, :free_flight_unavailable}

  @doc "Stop an empty private flight map when its only pilot disconnects."
  def stop_started(player_id, opts \\ []) when is_integer(player_id) and player_id > 0 do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    supervisor = Keyword.get(opts, :supervisor,
      Module.concat(SessionManager, FreeFlightMaps))
    case Registry.lookup(registry, {:world_map, map_id(player_id)}) do
      [{pid, _}] ->
        case DynamicSupervisor.terminate_child(supervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          error -> error
        end
      [] -> :ok
    end
  end

  @doc "Register the empty map before publishing a free-flight mode transition."
  @spec ensure_started(pos_integer(), keyword()) :: :ok | {:error, term()}
  def ensure_started(player_id, opts \\ []) when is_integer(player_id) and player_id > 0 do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    if MapServer.available?(registry, map_id(player_id)) do
      :ok
    else
      settings = Application.get_env(:core, Core.World, [])
      supervisor = Keyword.get(opts, :supervisor,
        Module.concat(SessionManager, FreeFlightMaps))
      server = Keyword.get(opts, :solar_navigation_server,
        Module.concat(SessionManager, Core.Universe.Navigation))
      child = {MapServer,
        definition: definition(player_id),
        registry: registry,
        tick_ms: Keyword.get(opts, :tick_ms, Keyword.get(settings, :tick_ms, 100)),
        event_sink: Keyword.get(opts, :event_sink,
          Keyword.get(settings, :event_sink, NoopEventSink)),
        solar_navigation_server: server,
        auto_tick: Keyword.get(opts, :auto_tick, Keyword.get(settings, :auto_tick, true)),
        initial_npcs?: false,
        auto_respawn?: false}

      case DynamicSupervisor.start_child(supervisor, child) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, :already_present} -> :ok
        error -> error
      end
    end
  end
end
