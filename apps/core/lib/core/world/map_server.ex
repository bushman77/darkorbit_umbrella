defmodule Core.World.MapServer do
  @moduledoc """
  Authoritative owner of entity positions and movement for one map.
  """

  use GenServer

  alias Core.Ships.Stats
  alias Core.World.Entity
  alias Core.World.EventSink
  alias Core.World.MapDefinition
  alias Core.World.Movement
  alias Core.World.Session

  def child_spec(opts) do
    definition = opts |> Keyword.fetch!(:definition) |> MapDefinition.new()

    %{
      id: {__MODULE__, definition.id},
      start: {__MODULE__, :start_link, [Keyword.put(opts, :definition, definition)]},
      restart: :permanent,
      type: :worker
    }
  end

  def start_link(opts) do
    definition = opts |> Keyword.fetch!(:definition) |> MapDefinition.new()
    registry = Keyword.fetch!(opts, :registry)
    name = via(registry, definition.id)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :definition, definition), name: name)
  end

  @spec join(atom(), String.t(), Session.t(), Stats.t() | map()) ::
          {:ok, map()} | {:error, term()}
  def join(registry, map_id, %Session{} = session, stats) do
    call_map(registry, map_id, {:join, session, stats})
  end

  @spec leave(atom(), String.t(), pos_integer(), term()) :: :ok | {:error, term()}
  def leave(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:leave, session_id, entity_id})
  end

  @spec move(atom(), String.t(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, term()}
  def move(registry, map_id, session_id, entity_id, destination) do
    call_map(registry, map_id, {:move, session_id, entity_id, destination})
  end

  @spec snapshot(atom(), String.t()) :: {:ok, map()} | {:error, :map_not_found}
  def snapshot(registry, map_id), do: call_map(registry, map_id, :snapshot)

  @spec tick(atom(), String.t()) :: {:ok, map()} | {:error, :map_not_found}
  def tick(registry, map_id), do: call_map(registry, map_id, :tick)

  @spec available?(atom(), String.t()) :: boolean()
  def available?(registry, map_id) do
    Registry.lookup(registry, {:world_map, map_id}) != []
  end

  @impl true
  def init(opts) do
    definition = Keyword.fetch!(opts, :definition)
    tick_ms = Keyword.fetch!(opts, :tick_ms)

    validate_definition!(definition)

    if not is_integer(tick_ms) or tick_ms <= 0 do
      raise ArgumentError, "world tick_ms must be a positive integer"
    end

    state = %{
      definition: definition,
      entities: %{},
      event_sink: Keyword.fetch!(opts, :event_sink),
      tick: 0,
      tick_ms: tick_ms,
      auto_tick?: Keyword.get(opts, :auto_tick, true)
    }

    {:ok, schedule_tick(state)}
  end

  @impl true
  def handle_call({:join, session, stats}, _from, state) do
    cond do
      Map.has_key?(state.entities, session.entity_id) ->
        {:reply, {:error, :entity_already_joined}, state}

      not valid_speed?(stats) ->
        {:reply, {:error, :invalid_ship_stats}, state}

      true ->
        entity = %Entity{
          id: session.entity_id,
          player_id: session.player_id,
          session_id: session.id,
          position: state.definition.spawn,
          destination: nil,
          speed: stats.speed
        }

        new_state = %{state | entities: Map.put(state.entities, entity.id, entity)}
        payload = public_entity(entity)
        broadcast(new_state, :entity_joined, payload)
        {:reply, {:ok, payload}, new_state}
    end
  end

  def handle_call({:leave, session_id, entity_id}, _from, state) do
    case authorized_entity(state, session_id, entity_id) do
      {:ok, entity} ->
        new_state = %{state | entities: Map.delete(state.entities, entity.id)}
        broadcast(new_state, :entity_left, public_entity(entity))
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:move, session_id, entity_id, destination}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         {:ok, destination} <- Movement.destination(state.definition, destination) do
      updated_entity = %{entity | destination: destination}
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}
      payload = public_entity(updated_entity)
      broadcast(new_state, :movement_started, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, public_state(state)}, state}

  def handle_call(:tick, _from, state) do
    new_state = advance_tick(state)
    {:reply, {:ok, public_state(new_state)}, new_state}
  end

  @impl true
  def handle_info(:simulation_tick, state) do
    new_state = state |> advance_tick() |> schedule_tick()
    {:noreply, new_state}
  end

  defp advance_tick(state) do
    distance_factor = state.tick_ms / 1_000

    entities =
      Map.new(state.entities, fn {entity_id, entity} ->
        {entity_id, advance_entity(entity, entity.speed * distance_factor)}
      end)

    new_state = %{state | entities: entities, tick: state.tick + 1}
    broadcast(new_state, :world_state, public_state(new_state))
    new_state
  end

  defp advance_entity(%Entity{destination: nil} = entity, _distance), do: entity

  defp advance_entity(%Entity{} = entity, distance) do
    case Movement.advance(entity.position, entity.destination, distance) do
      {position, :moving} -> %{entity | position: position}
      {position, :arrived} -> %{entity | position: position, destination: nil}
    end
  end

  defp authorized_entity(state, session_id, entity_id) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, %Entity{session_id: ^session_id} = entity} -> {:ok, entity}
      {:ok, %Entity{}} -> {:error, :session_mismatch}
      :error -> {:error, :entity_not_found}
    end
  end

  defp valid_speed?(%{speed: speed}) when is_number(speed) and speed >= 0, do: true
  defp valid_speed?(_stats), do: false

  defp validate_definition!(definition) do
    valid_dimensions? =
      is_number(definition.width) and definition.width > 0 and is_number(definition.height) and
        definition.height > 0

    valid_identity? =
      is_binary(definition.id) and definition.id != "" and is_binary(definition.name) and
        definition.name != ""

    valid_spawn? = match?({:ok, _position}, Movement.destination(definition, definition.spawn))

    if not (valid_dimensions? and valid_identity? and valid_spawn?) do
      raise ArgumentError, "invalid world map definition: #{inspect(definition)}"
    end
  end

  defp public_state(state) do
    entities =
      state.entities
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&public_entity/1)

    %{
      map_id: state.definition.id,
      tick: state.tick,
      tick_ms: state.tick_ms,
      boundaries: %{width: state.definition.width, height: state.definition.height},
      entities: entities
    }
  end

  defp public_entity(entity) do
    %{
      id: entity.id,
      player_id: entity.player_id,
      position: public_position(entity.position),
      destination: public_position(entity.destination),
      speed: entity.speed
    }
  end

  defp public_position(nil), do: nil
  defp public_position(position), do: %{x: position.x, y: position.y}

  defp broadcast(state, event, payload) do
    EventSink.dispatch(state.event_sink, state.definition.id, event, payload)
  end

  defp schedule_tick(%{auto_tick?: true} = state) do
    Process.send_after(self(), :simulation_tick, state.tick_ms)
    state
  end

  defp schedule_tick(state), do: state

  defp call_map(registry, map_id, message) do
    case Registry.lookup(registry, {:world_map, map_id}) do
      [{pid, _value}] -> GenServer.call(pid, message)
      [] -> {:error, :map_not_found}
    end
  end

  defp via(registry, map_id), do: {:via, Registry, {registry, {:world_map, map_id}}}
end
