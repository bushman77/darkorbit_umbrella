defmodule Core.World.MapServer do
  @moduledoc """
  Authoritative owner of player movement, NPC simulation, targeting, and combat
  for one map.
  """

  use GenServer

  alias Core.Combat
  alias Core.NPC.AI
  alias Core.NPC.Catalog, as: NPCCatalog
  alias Core.NPC.Entity, as: NPCEntity
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

  @spec select_target(atom(), String.t(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, term()}
  def select_target(registry, map_id, session_id, entity_id, target_id) do
    call_map(registry, map_id, {:select_target, session_id, entity_id, target_id})
  end

  @spec clear_target(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def clear_target(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:clear_target, session_id, entity_id})
  end

  @spec attack(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def attack(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:attack, session_id, entity_id})
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

    npc_catalog = Keyword.get(opts, :npc_catalog, NPCCatalog.all())

    npc_definitions =
      definition.id
      |> NPCCatalog.for_map(npc_catalog)
      |> Map.new(&{&1.id, &1})

    state = %{
      definition: definition,
      entities: %{},
      npcs: spawn_npcs(npc_definitions, tick_ms),
      npc_definitions: npc_definitions,
      respawns: %{},
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
      Map.has_key?(state.entities, session.entity_id) or
          Map.has_key?(state.npcs, session.entity_id) ->
        {:reply, {:error, :entity_already_joined}, state}

      not valid_stats?(stats) ->
        {:reply, {:error, :invalid_ship_stats}, state}

      true ->
        weapon = Combat.player_weapon(stats, state.tick_ms)

        entity = %Entity{
          id: session.entity_id,
          kind: :player,
          player_id: session.player_id,
          session_id: session.id,
          position: state.definition.spawn,
          destination: nil,
          speed: stats.speed,
          hull: stats.hit_points,
          max_hull: stats.hit_points,
          shields: stats.shields,
          max_shields: stats.shields,
          shield_absorption: stats.shield_absorption,
          damage: weapon.damage,
          attack_range: weapon.attack_range,
          attack_cooldown_ticks: weapon.attack_cooldown_ticks,
          next_attack_tick: 0,
          target_id: nil,
          status: :alive
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
        {npcs, cleared_npc_ids} = clear_npc_targets(state.npcs, entity.id)
        new_state = %{state | entities: Map.delete(state.entities, entity.id), npcs: npcs}
        broadcast(new_state, :entity_left, public_entity(entity))

        Enum.each(cleared_npc_ids, fn npc_id ->
          broadcast(new_state, :npc_state_changed, public_entity(Map.fetch!(npcs, npc_id)))
        end)

        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:move, session_id, entity_id, destination}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
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

  def handle_call({:select_target, session_id, entity_id, target_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
         {:ok, target} <- fetch_npc(state, target_id),
         true <- Combat.valid_target?(entity, target) do
      updated_entity = %{entity | target_id: target.id}
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}
      payload = %{player_id: entity.id, target_id: target.id, tick: state.tick}
      broadcast(new_state, :target_selected, payload)
      {:reply, {:ok, %{target: public_entity(target), selection: payload}}, new_state}
    else
      false -> {:reply, {:error, :invalid_target}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:clear_target, session_id, entity_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id) do
      updated_entity = %{entity | target_id: nil}
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}
      payload = %{player_id: entity.id, target_id: nil, tick: state.tick}
      broadcast(new_state, :target_cleared, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:attack, session_id, entity_id}, _from, state) do
    with {:ok, attacker} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(attacker),
         {:ok, target_id} <- selected_target(attacker),
         {:ok, target} <- fetch_npc(state, target_id),
         :ok <- Combat.validate_attack(attacker, target, state.tick) do
      {new_state, payload} = resolve_player_attack(state, attacker, target)
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
    next_tick = state.tick + 1
    distance_factor = state.tick_ms / 1_000

    entities =
      Map.new(state.entities, fn {entity_id, entity} ->
        distance = if Combat.alive?(entity), do: entity.speed * distance_factor, else: 0
        {entity_id, advance_entity(entity, distance)}
      end)

    {npcs, attack_actions, npc_events} =
      state.npcs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce({%{}, [], []}, fn npc, {npcs, actions, events} ->
        definition = Map.fetch!(state.npc_definitions, npc.npc_type_id)

        {decided_npc, new_actions} =
          AI.step(npc, Map.values(entities), definition, state.definition, next_tick)

        moved_npc = advance_entity(decided_npc, decided_npc.speed * distance_factor)
        npc_events = npc_events(npc, moved_npc)

        {
          Map.put(npcs, moved_npc.id, moved_npc),
          actions ++
            Enum.map(new_actions, fn {:attack, target_id} -> {moved_npc.id, target_id} end),
          events ++ Enum.map(npc_events, &{&1, moved_npc.id})
        }
      end)

    state = %{state | entities: entities, npcs: npcs, tick: next_tick}

    Enum.each(npc_events, fn {event, npc_id} ->
      broadcast(state, event, public_entity(Map.fetch!(state.npcs, npc_id)))
    end)

    state =
      Enum.reduce(attack_actions, state, fn action, current ->
        resolve_npc_attack(current, action)
      end)

    state = respawn_due_npcs(state)
    broadcast(state, :world_state, public_state(state))
    state
  end

  defp resolve_player_attack(state, attacker, target) do
    {damaged_target, damage} = Combat.apply_damage(target, attacker.damage)

    updated_attacker = %{
      attacker
      | next_attack_tick: Combat.next_attack_tick(attacker, state.tick)
    }

    state = %{
      state
      | entities: Map.put(state.entities, attacker.id, updated_attacker),
        npcs: Map.put(state.npcs, target.id, damaged_target)
    }

    payload = combat_payload(updated_attacker, damaged_target, damage, state.tick)
    broadcast(state, :laser_fired, payload)

    if damage.destroyed do
      destroy_npc(state, damaged_target, updated_attacker.id, payload)
    else
      {state, payload}
    end
  end

  defp resolve_npc_attack(state, {npc_id, player_id}) do
    with {:ok, attacker} <- Map.fetch(state.npcs, npc_id),
         {:ok, target} <- Map.fetch(state.entities, player_id),
         :ok <- Combat.validate_attack(attacker, target, state.tick) do
      {damaged_target, damage} = Combat.apply_damage(target, attacker.damage)

      updated_attacker = %{
        attacker
        | next_attack_tick: Combat.next_attack_tick(attacker, state.tick)
      }

      state = %{
        state
        | entities: Map.put(state.entities, target.id, damaged_target),
          npcs: Map.put(state.npcs, attacker.id, updated_attacker)
      }

      payload = combat_payload(updated_attacker, damaged_target, damage, state.tick)
      broadcast(state, :laser_fired, payload)

      state =
        if damage.destroyed do
          {npcs, _cleared} = clear_npc_targets(state.npcs, damaged_target.id)
          destroyed_state = %{state | npcs: npcs}

          broadcast(destroyed_state, :entity_destroyed, %{
            entity: public_entity(damaged_target),
            attacker_id: updated_attacker.id,
            tick: destroyed_state.tick,
            respawn_tick: nil
          })

          destroyed_state
        else
          state
        end

      state
    else
      _invalid_attack -> state
    end
  end

  defp destroy_npc(state, npc, attacker_id, attack_payload) do
    due_tick = state.tick + npc.respawn_delay_ticks
    respawn = %{npc_type_id: npc.npc_type_id, spawn_index: npc.spawn_index, due_tick: due_tick}

    entities =
      Map.new(state.entities, fn {entity_id, entity} ->
        if entity.target_id == npc.id do
          {entity_id, %{entity | target_id: nil}}
        else
          {entity_id, entity}
        end
      end)

    state = %{
      state
      | entities: entities,
        npcs: Map.delete(state.npcs, npc.id),
        respawns: Map.put(state.respawns, npc.id, respawn)
    }

    broadcast(state, :entity_destroyed, %{
      entity: public_entity(npc),
      attacker_id: attacker_id,
      tick: state.tick,
      respawn_tick: due_tick
    })

    {state, Map.put(attack_payload, :respawn_tick, due_tick)}
  end

  defp respawn_due_npcs(state) do
    {due, pending} =
      state.respawns
      |> Enum.split_with(fn {_npc_id, respawn} -> respawn.due_tick <= state.tick end)

    state = %{state | respawns: Map.new(pending)}

    Enum.reduce(due, state, fn {_npc_id, respawn}, current ->
      definition = Map.fetch!(current.npc_definitions, respawn.npc_type_id)
      npc = NPCEntity.spawn(definition, respawn.spawn_index, current.tick_ms)
      new_state = %{current | npcs: Map.put(current.npcs, npc.id, npc)}
      broadcast(new_state, :npc_spawned, public_entity(npc))
      new_state
    end)
  end

  defp advance_entity(%{destination: nil} = entity, _distance), do: entity

  defp advance_entity(entity, distance) do
    case Movement.advance(entity.position, entity.destination, distance) do
      {position, :moving} -> %{entity | position: position}
      {position, :arrived} -> %{entity | position: position, destination: nil}
    end
  end

  defp npc_events(previous, current) do
    state_events =
      if previous.state != current.state or previous.target_id != current.target_id,
        do: [:npc_state_changed],
        else: []

    if is_nil(previous.destination) and not is_nil(current.destination) do
      [:npc_movement_started | state_events]
    else
      state_events
    end
  end

  defp authorized_entity(state, session_id, entity_id) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, %Entity{session_id: ^session_id} = entity} -> {:ok, entity}
      {:ok, %Entity{}} -> {:error, :session_mismatch}
      :error -> {:error, :entity_not_found}
    end
  end

  defp fetch_npc(state, target_id) do
    case Map.fetch(state.npcs, target_id) do
      {:ok, npc} -> {:ok, npc}
      :error -> {:error, :target_not_found}
    end
  end

  defp selected_target(%Entity{target_id: nil}), do: {:error, :no_target}
  defp selected_target(%Entity{target_id: target_id}), do: {:ok, target_id}

  defp living_attacker(entity) do
    if Combat.alive?(entity), do: :ok, else: {:error, :attacker_destroyed}
  end

  defp valid_stats?(stats) do
    valid_non_negative_number?(Map.get(stats, :speed)) and
      valid_non_negative_integer?(Map.get(stats, :hit_points), positive?: true) and
      valid_non_negative_integer?(Map.get(stats, :shields)) and
      valid_non_negative_integer?(Map.get(stats, :damage)) and
      valid_absorption?(Map.get(stats, :shield_absorption))
  end

  defp valid_non_negative_number?(value), do: is_number(value) and value >= 0

  defp valid_non_negative_integer?(value, opts \\ []) do
    minimum = if Keyword.get(opts, :positive?, false), do: 1, else: 0
    is_integer(value) and value >= minimum
  end

  defp valid_absorption?(value), do: is_number(value) and value >= 0 and value <= 1

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
      (Map.values(state.entities) ++ Map.values(state.npcs))
      |> Enum.sort_by(fn entity -> {entity_sort_order(entity), to_string(entity.id)} end)
      |> Enum.map(&public_entity/1)

    %{
      map_id: state.definition.id,
      tick: state.tick,
      tick_ms: state.tick_ms,
      boundaries: %{width: state.definition.width, height: state.definition.height},
      entities: entities
    }
  end

  defp public_entity(%Entity{} = entity) do
    %{
      id: entity.id,
      kind: entity.kind,
      player_id: entity.player_id,
      position: public_position(entity.position),
      destination: public_position(entity.destination),
      speed: entity.speed,
      hull: entity.hull,
      max_hull: entity.max_hull,
      shields: entity.shields,
      max_shields: entity.max_shields,
      shield_absorption: entity.shield_absorption,
      damage: entity.damage,
      attack_range: entity.attack_range,
      target_id: entity.target_id,
      status: entity.status
    }
  end

  defp public_entity(%NPCEntity{} = entity) do
    %{
      id: entity.id,
      kind: entity.kind,
      npc_type_id: entity.npc_type_id,
      display_name: entity.display_name,
      position: public_position(entity.position),
      destination: public_position(entity.destination),
      speed: entity.speed,
      hull: entity.hull,
      max_hull: entity.max_hull,
      shields: entity.shields,
      max_shields: entity.max_shields,
      shield_absorption: entity.shield_absorption,
      damage: entity.damage,
      attack_range: entity.attack_range,
      target_id: entity.target_id,
      state: entity.state,
      status: entity.status
    }
  end

  defp public_position(nil), do: nil
  defp public_position(position), do: %{x: position.x, y: position.y}

  defp combat_payload(attacker, target, damage, tick) do
    %{
      attacker_id: attacker.id,
      target_id: target.id,
      damage: damage.requested_damage,
      shield_damage: damage.shield_damage,
      hull_damage: damage.hull_damage,
      destroyed: damage.destroyed,
      target: %{
        id: target.id,
        hull: target.hull,
        max_hull: target.max_hull,
        shields: target.shields,
        max_shields: target.max_shields,
        status: target.status
      },
      tick: tick
    }
  end

  defp clear_npc_targets(npcs, player_id) do
    Enum.reduce(npcs, {%{}, []}, fn {npc_id, npc}, {updated, cleared} ->
      if npc.target_id == player_id do
        cleared_npc = %{npc | state: :idle, target_id: nil, destination: nil}
        {Map.put(updated, npc_id, cleared_npc), [npc_id | cleared]}
      else
        {Map.put(updated, npc_id, npc), cleared}
      end
    end)
  end

  defp spawn_npcs(definitions, tick_ms) do
    definitions
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.flat_map(fn definition ->
      definition.spawn.positions
      |> Enum.with_index()
      |> Enum.map(fn {_position, index} -> NPCEntity.spawn(definition, index, tick_ms) end)
    end)
    |> Map.new(&{&1.id, &1})
  end

  defp entity_sort_order(%{kind: :player}), do: 0
  defp entity_sort_order(%{kind: :npc}), do: 1

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
