defmodule Core.World.MapServer do
  @moduledoc """
  Authoritative owner of player movement, NPC simulation, targeting, and combat
  for one map.
  """

  use GenServer

  alias Core.Combat
  alias Core.Combat.ActionCatalog
  alias Core.NPC.AI
  alias Core.NPC.Catalog, as: NPCCatalog
  alias Core.NPC.CruiseRoute
  alias Core.NPC.Entity, as: NPCEntity
  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.Ships.Stats
  alias Core.World.Course
  alias Core.World.Entity
  alias Core.World.FlightDynamics
  alias Core.World.EventSink
  alias Core.World.MapDefinition
  alias Core.World.Movement
  alias Core.World.Orientation
  alias Core.World.PlanetaryCollision
  alias Core.World.PlanetaryProximity
  alias Core.World.Position
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
  def join(registry, map_id, %Session{} = session, stats, entry \\ nil) do
    call_map(registry, map_id, {:join, session, stats, entry})
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

  @spec plot_course(atom(), String.t(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, term()}
  def plot_course(registry, map_id, session_id, entity_id, waypoints) do
    call_map(registry, map_id, {:plot_course, session_id, entity_id, waypoints})
  end

  @spec stop_navigation(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def stop_navigation(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:stop_navigation, session_id, entity_id})
  end

  @spec flight_controls(atom(), String.t(), pos_integer(), term(), map()) ::
          {:ok, map()} | {:error, term()}
  def flight_controls(registry, map_id, session_id, entity_id, input) do
    call_map(registry, map_id, {:flight_controls, session_id, entity_id, input})
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

  @spec engage_combat(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def engage_combat(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:engage_combat, session_id, entity_id})
  end

  @spec disengage_combat(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def disengage_combat(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:disengage_combat, session_id, entity_id})
  end

  @spec toggle_laser_fire(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def toggle_laser_fire(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:toggle_laser_fire, session_id, entity_id})
  end

  @spec activate_action(atom(), String.t(), pos_integer(), term(), term()) ::
          {:ok, map()} | {:error, term()}
  def activate_action(registry, map_id, session_id, entity_id, slot) do
    call_map(registry, map_id, {:activate_action, session_id, entity_id, slot})
  end

  @spec fire_ready_weapon(atom(), String.t(), pos_integer(), term()) ::
          {:ok, map()} | {:error, term()}
  def fire_ready_weapon(registry, map_id, session_id, entity_id) do
    call_map(registry, map_id, {:fire_ready_weapon, session_id, entity_id})
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

  @doc "Administrative encounter cleanup. Never a client command."
  @spec clear_encounters(atom(), String.t()) :: :ok | {:error, term()}
  def clear_encounters(registry, map_id),
    do: call_map(registry, map_id, :clear_encounters)

  @doc "Create a server-authorized encounter. Not exposed directly to clients."
  @spec start_encounter(atom(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def start_encounter(registry, map_id, npc_type_id) when is_binary(npc_type_id),
    do: call_map(registry, map_id, {:start_encounter, npc_type_id})

  @doc "Spawn an encounter NPC for the authenticated pilot in their current map."
  @spec start_solar_tactical(atom(), String.t(), pos_integer(), term(), String.t(), String.t(), String.t(), boolean(), map()) ::
          {:ok, map()} | {:error, term()}
  def start_solar_tactical(registry, map_id, session_id, player_id, encounter_id,
          call_sign, ship_class, aggressive?, course)
      when is_integer(player_id) and is_binary(encounter_id) and is_binary(call_sign) and
           is_binary(ship_class) and is_boolean(aggressive?) and is_map(course) do
    call_map(registry, map_id,
      {:start_solar_tactical, session_id, player_id, encounter_id,
       call_sign, ship_class, aggressive?, course})
  end

  @doc "Server-authorized victory verification or safe retreat."
  @spec finish_solar_tactical(atom(), String.t(), pos_integer(), term(), String.t(), atom()) ::
          :ok | {:error, term()}
  def finish_solar_tactical(registry, map_id, session_id, player_id, encounter_id, outcome)
      when outcome in [:victory, :retreat, :defeat, :surrender] do
    call_map(registry, map_id,
      {:finish_solar_tactical, session_id, player_id, encounter_id, outcome})
  end

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
      # An Atlas session begins peacefully. Definitions remain dormant.
      npcs: if(Keyword.get(opts, :initial_npcs?, false),
        do: spawn_npcs(npc_definitions, tick_ms), else: %{}),
      npc_definitions: npc_definitions,
      respawns: %{},
      solar_tactical: %{},
      solar_navigation_server: Keyword.get(opts, :solar_navigation_server),
      auto_respawn?: Keyword.get(opts, :auto_respawn?, false),
      event_sink: Keyword.fetch!(opts, :event_sink),
      tick: 0,
      tick_ms: tick_ms,
      auto_tick?: Keyword.get(opts, :auto_tick, true)
    }

    {:ok, schedule_tick(state)}
  end

  @impl true
  def handle_call({:join, session, stats}, from, state),
    do: handle_call({:join, session, stats, nil}, from, state)

  def handle_call({:join, session, stats, entry}, _from, state) do
    cond do
      Map.has_key?(state.entities, session.entity_id) or
          Map.has_key?(state.npcs, session.entity_id) ->
        {:reply, {:error, :entity_already_joined}, state}

      not valid_stats?(stats) ->
        {:reply, {:error, :invalid_ship_stats}, state}

      not valid_join_entry?(state.definition, entry) ->
        {:reply, {:error, :invalid_spawn}, state}

      true ->
        weapon = Combat.player_weapon(stats, state.tick_ms)
        position = if entry, do: entry.position, else: state.definition.spawn
        attitude = if entry, do: entry.attitude,
          else: %{yaw: 0.0, pitch: 0.0, roll: 0.0}

        entity = %Entity{
          id: session.entity_id,
          kind: :player,
          player_id: session.player_id,
          session_id: session.id,
          position: position,
          attitude: attitude,
          orientation: Orientation.from_angles(attitude),
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
          engaged_target_id: nil,
          status: :alive
        }

        new_state = %{state | entities: Map.put(state.entities, entity.id, entity)}
        payload = public_entity(entity)
        broadcast(new_state, :entity_joined, payload)
        {:reply, {:ok, payload}, new_state}
    end
  end

  def handle_call(:clear_encounters, _from, state) do
    entities =
      Map.new(state.entities, fn {id, entity} ->
        if Map.has_key?(state.npcs, entity.target_id) or
           Map.has_key?(state.npcs, entity.engaged_target_id) do
          {id, %{entity | target_id: nil, engaged_target_id: nil}}
        else
          {id, entity}
        end
      end)
    cleared = %{state | npcs: %{}, respawns: %{}, solar_tactical: %{}, entities: entities}
    Enum.each(state.npcs, fn {_id, npc} ->
      broadcast(cleared, :entity_left, public_entity(npc))
    end)
    {:reply, :ok, cleared}
  end

  def handle_call({:start_encounter, npc_type_id}, _from, state) do
    with {:ok, definition} <- NPCCatalog.fetch(npc_type_id, state.npc_definitions),
         [_position | _] <- definition.spawn.positions do
      npc = NPCEntity.spawn(definition, 0, state.tick_ms)
      if Map.has_key?(state.npcs, npc.id) or Map.has_key?(state.respawns, npc.id) do
        {:reply, {:error, :encounter_active}, state}
      else
        new_state = %{state | npcs: Map.put(state.npcs, npc.id, npc)}
        broadcast(new_state, :npc_spawned, public_entity(npc))
        {:reply, {:ok, public_entity(npc)}, new_state}
      end
    else
      :error -> {:reply, {:error, :unknown_npc_type}, state}
      [] -> {:reply, {:error, :no_spawn_position}, state}
    end
  end

  def handle_call(
        {:start_solar_tactical, session_id, player_id, encounter_id,
         call_sign, ship_class, aggressive?, route},
        _from, state
      ) do
    with :ok <- validate_tactical_ship_class(ship_class),
         {:ok, ship} <- authorized_entity(state, session_id, player_id),
         :ok <- living_attacker(ship),
         false <- Map.has_key?(state.solar_tactical, player_id),
         {:ok, base} <- NPCCatalog.fetch(ship_class, NPCCatalog.all()),
         {:ok, spawn} <- solar_tactical_position(state.definition, ship),
         {:ok, cruise_course} <- tactical_course(ship_class, route, spawn, state.definition) do
      type_id = "solar-" <> ship_class <> "-" <> Integer.to_string(player_id)
      definition = %{base |
        id: type_id,
        display_name: call_sign,
        spawn: %{base.spawn | map_id: state.definition.id, positions: [spawn],
          patrol_radius: 180.0}}
      npc = NPCEntity.spawn(definition, 0, state.tick_ms)
      npc =
        if cruise_course do
          %{npc | state: :cruise, destination: cruise_course.destination,
            course: Map.take(cruise_course,
              [:origin_id, :destination_id, :heading, :deflected?])}
        else
          npc
        end

      if Map.has_key?(state.npcs, npc.id) do
        {:reply, {:error, :encounter_active}, state}
      else
        updated = %{state |
          npcs: Map.put(state.npcs, npc.id, npc),
          npc_definitions: Map.put(state.npc_definitions, type_id, definition),
          solar_tactical: Map.put(state.solar_tactical, player_id,
            %{encounter_id: encounter_id, npc_id: npc.id, type_id: type_id,
              navigation_player_id: ship.player_id, provoked?: aggressive?})
        }
        broadcast(updated, :npc_spawned, public_entity(npc))
        {:reply, {:ok, public_entity(npc)}, updated}
      end
    else
      true -> {:reply, {:error, :encounter_active}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call(
        {:finish_solar_tactical, session_id, player_id, encounter_id, outcome},
        _from, state
      ) do
    with {:ok, ship} <- authorized_entity(state, session_id, player_id),
         {:ok, ongoing} <- Map.fetch(state.solar_tactical, player_id),
         true <- ongoing.encounter_id == encounter_id do
      present = Map.get(state.npcs, ongoing.npc_id)

      cond do
        outcome == :victory and present != nil ->
          {:reply, {:error, :enemy_still_active}, state}

        outcome == :surrender and (present == nil or present.state != :surrendered) ->
          {:reply, {:error, :enemy_not_surrendered}, state}

        outcome == :retreat and not Combat.alive?(ship) ->
          {:reply, {:error, :attacker_destroyed}, state}

        outcome == :defeat and Combat.alive?(ship) ->
          {:reply, {:error, :pilot_still_alive}, state}

        true ->
          # Retreat must clear stale target locks for every pilot that may
          # have targeted this now-removed encounter NPC.
          {entities, cleared} =
            Enum.reduce(state.entities, {%{}, []}, fn {id, entity}, {acc, refs} ->
              if entity.target_id == ongoing.npc_id or
                   entity.engaged_target_id == ongoing.npc_id do
                revised = %{entity | target_id: nil, engaged_target_id: nil}
                {Map.put(acc, id, revised), [entity | refs]}
              else
                {Map.put(acc, id, entity), refs}
              end
            end)

          updated = %{state |
            entities: entities,
            npcs: Map.delete(state.npcs, ongoing.npc_id),
            npc_definitions: Map.delete(state.npc_definitions, ongoing.type_id),
            solar_tactical: Map.delete(state.solar_tactical, player_id)
          }
          if present, do: broadcast(updated, :entity_left, public_entity(present))

          Enum.each(cleared, fn entity ->
            if entity.target_id != nil do
              broadcast(updated, :target_cleared, %{
                player_id: entity.id, target_id: nil, tick: state.tick})
            end
            if entity.engaged_target_id != nil do
              broadcast(updated, :combat_disengaged,
                disengagement_payload(entity, :target_removed, state.tick))
            end
          end)
          {:reply, :ok, updated}
      end
    else
      :error -> {:reply, {:error, :no_tactical_encounter}, state}
      false -> {:reply, {:error, :encounter_mismatch}, state}
      error -> {:reply, error, state}
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
      updated_entity = %{
        entity | destination: destination, route_waypoints: [], navigation_mode: :manual,
                 throttle: 0.0, cruise_speed: 0.0, velocity: %{x: 0.0, y: 0.0, z: 0.0},
                 rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0}, angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
      }
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}
      payload = public_entity(updated_entity)
      broadcast(new_state, :movement_started, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:plot_course, session_id, entity_id, waypoints}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
         {:ok, [first | remaining]} <- Course.plan(state.definition, waypoints) do
      updated = %{
        entity | destination: first, route_waypoints: remaining, navigation_mode: :autopilot,
                 throttle: 0.0, cruise_speed: 0.0, velocity: %{x: 0.0, y: 0.0, z: 0.0},
                 rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0}, angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
      }
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated)}
      payload = public_entity(updated)
      broadcast(new_state, :movement_started, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:stop_navigation, session_id, entity_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id) do
      updated = %{
        entity | destination: nil, route_waypoints: [], navigation_mode: :manual,
                 throttle: 0.0, cruise_speed: 0.0, velocity: %{x: 0.0, y: 0.0, z: 0.0},
                 rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0}, angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
      }
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated)}
      payload = public_entity(updated)
      broadcast(new_state, :movement_started, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:flight_controls, session_id, entity_id, input}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
         {:ok, updated} <- FlightDynamics.controls(entity, input, state.tick) do
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated)}
      payload = public_entity(updated)
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
      changing_target? = entity.target_id != target.id

      updated_entity = %{
        entity
        | target_id: target.id,
          engaged_target_id: if(changing_target?, do: nil, else: entity.engaged_target_id)
      }

      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}

      if changing_target? and not is_nil(entity.engaged_target_id) do
        broadcast(
          new_state,
          :combat_disengaged,
          disengagement_payload(entity, :target_changed, state.tick)
        )
      end

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
      updated_entity = %{entity | target_id: nil, engaged_target_id: nil}
      new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}

      if not is_nil(entity.engaged_target_id) do
        broadcast(
          new_state,
          :combat_disengaged,
          disengagement_payload(entity, :target_cleared, state.tick)
        )
      end

      payload = %{player_id: entity.id, target_id: nil, tick: state.tick}
      broadcast(new_state, :target_cleared, payload)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:engage_combat, session_id, entity_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
         {:ok, target_id} <- selected_target(entity),
         {:ok, target} <- fetch_npc(state, target_id),
         true <- Combat.valid_target?(entity, target),
         :ok <- armed_weapon(entity) do
      {new_state, payload} = engage_entity(state, entity, target, ActionCatalog.x1_laser())
      {:reply, {:ok, payload}, new_state}
    else
      false -> {:reply, {:error, :invalid_target}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:disengage_combat, session_id, entity_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id) do
      {new_state, payload} = clear_player_combat(state, entity, :cancelled)
      {:reply, {:ok, payload}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:toggle_laser_fire, session_id, entity_id}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity) do
      case toggle_laser_fire(state, entity, ActionCatalog.x1_laser()) do
        {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
        {new_state, payload} -> {:reply, {:ok, payload}, new_state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:activate_action, session_id, entity_id, slot}, _from, state) do
    with {:ok, entity} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(entity),
         {:ok, action} <- ActionCatalog.fetch_slot(slot) do
      activate_action(state, entity, slot, action)
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:fire_ready_weapon, session_id, entity_id}, _from, state) do
    with {:ok, attacker} <- authorized_entity(state, session_id, entity_id),
         :ok <- living_attacker(attacker),
         :ok <- armed_weapon(attacker),
         true <- Combat.cooldown_ready?(state.tick, attacker.next_attack_tick) do
      orientation = attacker.orientation || Orientation.from_angles(attacker.attitude)
      shots =
        Core.Combat.LineOfFire.trace_pair(
          attacker.position, orientation, Map.values(state.npcs), attacker.attack_range
        )

      {next_state, payload} = resolve_manual_wing_burst(state, attacker, shots)
      {:reply, {:ok, payload}, next_state}
    else
      false -> {:reply, {:error, :weapon_cooldown}, state}
      error -> {:reply, error, state}
    end
  end

  # One synchronized weapon activation. When both beams strike the same
  # NPC, combine the damage once; if two NPCs intersect separate rays,
  # distribute that same authorized damage budget across both.
  defp resolve_manual_wing_burst(state, attacker, shots) do
    hits_by_target =
      shots
      |> Enum.filter(& &1.hit)
      |> Enum.group_by(& &1.target_id)

    total_connections = Enum.count(shots, & &1.hit)
    ordered_targets = hits_by_target |> Map.keys() |> Enum.sort_by(&to_string/1)

    {npcs, impacts} =
      Enum.reduce(ordered_targets, {state.npcs, []}, fn id, {npcs, impacts} ->
        target = Map.fetch!(npcs, id)
        connected = length(Map.fetch!(hits_by_target, id))
        amount = if length(ordered_targets) == 1,
          do: attacker.damage,
          else: max(1, div(attacker.damage * connected, total_connections))

        {damaged, damage} = Combat.apply_damage(target, amount)
        updated = maybe_scow_survival(damaged)
        impact = %{
          target_id: id,
          target: combat_target_state(updated),
          damage: damage.requested_damage,
          shield_damage: damage.shield_damage,
          hull_damage: damage.hull_damage,
          destroyed: damage.destroyed,
          beams_hit: connected
        }

        {Map.put(npcs, id, updated), impacts ++ [impact]}
      end)

    updated_attacker =
      %{attacker | next_attack_tick: Combat.next_attack_tick(attacker, state.tick)}

    updated_state = %{
      state |
      entities: Map.put(state.entities, attacker.id, updated_attacker),
      npcs: npcs
    }
    |> provoke_tactical_contacts(Enum.map(impacts, & &1.target_id))

    first = List.first(impacts)
    visual_beams =
      Enum.map(shots, fn shot ->
        Map.take(shot, [:side, :from, :to, :hit, :target_id])
      end)

    payload = %{
      attacker_id: attacker.id,
      target_id: if(first, do: first.target_id, else: nil),
      target: if(first, do: first.target, else: nil),
      hits: impacts,
      hit: impacts != [],
      beams: visual_beams,
      from: position_3d(attacker.position),
      to: hd(shots).to,
      damage: Enum.sum(Enum.map(impacts, & &1.damage)),
      shield_damage: Enum.sum(Enum.map(impacts, & &1.shield_damage)),
      hull_damage: Enum.sum(Enum.map(impacts, & &1.hull_damage)),
      destroyed: Enum.any?(impacts, & &1.destroyed),
      next_attack_tick: updated_attacker.next_attack_tick,
      tick: state.tick
    }

    broadcast(updated_state, :laser_fired, payload)

    final_state =
      Enum.reduce(impacts, updated_state, fn impact, acc ->
        if impact.destroyed do
          destroyed = Map.fetch!(acc.npcs, impact.target_id)
          {after_destroy, _} = destroy_npc(acc, destroyed, attacker.id, payload)
          after_destroy
        else
          acc
        end
      end)

    {final_state, payload}
  end

  defp combat_target_state(target) do
    %{
      id: target.id, hull: target.hull, max_hull: target.max_hull,
      shields: target.shields, max_shields: target.max_shields,
      status: target.status
    }
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

    # Apply one authoritative swept planet test after either manual thrust
    # OR plotted autopilot movement. Even a single fast tick that enters and
    # exits the sphere must register a fatal impact.
    {entities, impacts, proximity_changes} =
      state.entities
      |> Enum.sort_by(fn {id, _} -> inspect(id) end)
      |> Enum.reduce({%{}, [], []}, fn {entity_id, entity}, {entities, impacts, changes} ->
        moved =
          cond do
            not Combat.alive?(entity) -> entity
            entity.destination != nil -> advance_entity(entity, entity.speed * distance_factor)
            true -> FlightDynamics.step(entity, state.definition, distance_factor, next_tick)
          end

        case PlanetaryCollision.resolve(entity, moved, state.definition) do
          {:ok, safe} ->
            change =
              if Combat.alive?(safe) do
                PlanetaryProximity.transition(
                  entity_id,
                  PlanetaryProximity.warning(entity.position, state.definition),
                  PlanetaryProximity.warning(safe.position, state.definition),
                  next_tick
                )
              end

            changes = if change, do: [change | changes], else: changes
            {Map.put(entities, entity_id, safe), impacts, changes}

          {:crashed, destroyed} ->
            # A fatal collision is announced by :entity_destroyed, not an
            # inaccurate 'all clear' or intermediate caution signal.
            {Map.put(entities, entity_id, destroyed),
             [{entity, destroyed} | impacts], changes}
        end
      end)

    state = %{state | entities: entities, tick: next_tick}

    # Level changes only. Repeated position/clearance changes are available
    # in the authoritative world snapshot without flooding channel events.
    Enum.each(Enum.reverse(proximity_changes), fn change ->
      broadcast(state, :planetary_proximity_changed, change)
    end)

    state =
      impacts
      |> Enum.reverse()
      |> Enum.reduce(state, fn {previous, destroyed}, current ->
        {npcs, _cleared} = clear_npc_targets(current.npcs, destroyed.id)
        current = %{current | npcs: npcs}

        if not is_nil(previous.engaged_target_id) do
          broadcast(current, :combat_disengaged,
            disengagement_payload(previous, :player_destroyed, next_tick))
        end

        if not is_nil(previous.target_id) do
          broadcast(current, :target_cleared, %{
            player_id: previous.id, target_id: nil, tick: next_tick
          })
        end

        broadcast(current, :entity_destroyed, %{
          entity: public_entity(destroyed),
          reason: :planetary_collision,
          planet_id: current.definition.planet.body_id,
          attacker_id: nil,
          tick: next_tick,
          respawn_tick: nil
        })

        current
      end)

    {npcs, attack_actions, npc_events, finished_courses} =
      state.npcs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce({%{}, [], [], []}, fn npc, {npcs, actions, events, finished} ->
        definition = Map.fetch!(state.npc_definitions, npc.npc_type_id)

        {decided_npc, new_actions} =
          AI.step(npc, tactical_targets(state, npc, entities),
            definition, state.definition, next_tick)

        moved_npc = advance_entity(decided_npc, decided_npc.speed * distance_factor)

        if npc.state in [:cruise, :evade] and npc.destination != nil and
             moved_npc.destination == nil do
          # This Scow left the local interception lane. Do not spawn a new
          # patrol waypoint or allow it to circle back to its pursuer.
          {npcs, actions, events, [moved_npc | finished]}
        else
          changed = npc_events(npc, moved_npc)

          {
            Map.put(npcs, moved_npc.id, moved_npc),
            actions ++
              Enum.map(new_actions, fn {:attack, target_id} -> {moved_npc.id, target_id} end),
            events ++ Enum.map(changed, &{&1, moved_npc.id}),
            finished
          }
        end
      end)

    state = %{state | npcs: npcs}

    Enum.each(npc_events, fn {event, npc_id} ->
      broadcast(state, event, public_entity(Map.fetch!(state.npcs, npc_id)))
    end)

    state =
      Enum.reduce(attack_actions, state, fn action, current ->
        resolve_npc_attack(current, action)
      end)

    state = state |> resolve_player_engagements() |> respawn_due_npcs()
    state = complete_tactical_courses(state, Enum.reverse(finished_courses))
    broadcast(state, :world_state, public_state(state))
    state
  end

  defp complete_tactical_courses(state, ships) do
    Enum.reduce(ships, state, fn npc, current ->
      case Enum.find(current.solar_tactical, fn {_owner, held} ->
             held.npc_id == npc.id
           end) do
        {owner_id, held} ->
          {entities, cleared} =
            Enum.reduce(current.entities, {%{}, []}, fn {id, ship}, {acc, releases} ->
              if ship.target_id == npc.id or ship.engaged_target_id == npc.id do
                updated = %{ship | target_id: nil, engaged_target_id: nil}
                {Map.put(acc, id, updated), [ship | releases]}
              else
                {Map.put(acc, id, ship), releases}
              end
            end)

          updated = %{current |
            entities: entities,
            solar_tactical: Map.delete(current.solar_tactical, owner_id),
            npc_definitions: Map.delete(current.npc_definitions, held.type_id)}

          broadcast(updated, :entity_left, public_entity(npc))

          Enum.each(cleared, fn ship ->
            if ship.target_id != nil do
              broadcast(updated, :target_cleared,
                %{player_id: ship.id, target_id: nil, tick: current.tick})
            end
            if ship.engaged_target_id != nil do
              broadcast(updated, :combat_disengaged,
                disengagement_payload(ship, :target_removed, current.tick))
            end
          end)

          # Unlike relying on a browser/channel event, this must work even
          # when the pilot loses Wi-Fi while the Scow crosses the lane.
          case {current.solar_navigation_server, held.navigation_player_id} do
            {server, player_id} when not is_nil(server) and
                                     is_integer(player_id) and player_id > 0 ->
              _ = SolarNavigation.finish_tactical(server, player_id, held.encounter_id, :escaped)

            _ ->
              :ok
          end

          updated

        nil ->
          current
      end
    end)
  end

  defp resolve_player_engagements(state) do
    state.entities
    |> Map.keys()
    |> Enum.sort_by(&inspect/1)
    |> Enum.reduce(state, fn entity_id, current ->
      case Map.fetch(current.entities, entity_id) do
        {:ok, %Entity{engaged_target_id: nil}} ->
          current

        {:ok, %Entity{} = attacker} ->
          resolve_player_engagement(current, attacker)

        :error ->
          current
      end
    end)
  end

  defp resolve_player_engagement(state, attacker) do
    with :ok <- living_attacker(attacker),
         {:ok, target} <- fetch_npc(state, attacker.engaged_target_id),
         true <- attacker.target_id == target.id,
         :ok <- Combat.validate_attack(attacker, target, state.tick) do
      {new_state, _payload} = resolve_player_attack(state, attacker, target)
      new_state
    else
      {:error, reason} when reason in [:weapon_cooldown, :out_of_range] ->
        state

      false ->
        state |> clear_player_combat(attacker, :target_invalid) |> elem(0)

      {:error, reason} ->
        state |> clear_player_combat(attacker, engagement_error_reason(reason)) |> elem(0)
    end
  end

  defp resolve_player_attack(state, attacker, target, beam \\ nil) do
    {damaged_target, damage} = Combat.apply_damage(target, attacker.damage)
    damaged_target = maybe_scow_survival(damaged_target)

    updated_attacker = %{
      attacker
      | next_attack_tick: Combat.next_attack_tick(attacker, state.tick)
    }

    state = %{
      state
      | entities: Map.put(state.entities, attacker.id, updated_attacker),
        npcs: Map.put(state.npcs, target.id, damaged_target)
    }
    |> provoke_tactical_contacts([target.id])

    payload =
      combat_payload(updated_attacker, damaged_target, damage, state.tick)
      |> Map.put(:hit, true)
      |> maybe_add_beam(beam)
      |> maybe_add_player_wing_beams(attacker, target, beam)
    broadcast(state, :laser_fired, payload)

    if damage.destroyed do
      destroy_npc(state, damaged_target, updated_attacker.id, payload)
    else
      {state, payload}
    end
  end

  defp maybe_add_beam(payload, nil), do: payload
  defp maybe_add_beam(payload, beam), do: Map.merge(payload, beam)

  defp maybe_add_player_wing_beams(payload, attacker, target, nil) do
    orientation = attacker.orientation || Orientation.from_angles(attacker.attitude)
    beams = Core.Combat.LineOfFire.locked_pair(
      attacker.position, orientation, target.position
    )
    Map.put(payload, :beams, beams)
  end
  defp maybe_add_player_wing_beams(payload, _attacker, _target, _beam), do: payload

  defp resolve_npc_attack(state, {npc_id, player_id}) do
    with {:ok, attacker} <- Map.fetch(state.npcs, npc_id),
         {:ok, target} <- Map.fetch(state.entities, player_id),
         :ok <- Combat.validate_attack(attacker, target, state.tick) do
      {damaged_target, damage} = Combat.apply_damage(target, attacker.damage)

      damaged_target =
        if damage.destroyed do
          %{damaged_target | destination: nil, route_waypoints: [], navigation_mode: :manual}
        else
          damaged_target
        end

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

          if not is_nil(target.engaged_target_id) do
            broadcast(
              destroyed_state,
              :combat_disengaged,
              disengagement_payload(target, :player_destroyed, destroyed_state.tick)
            )
          end

          if not is_nil(target.target_id) do
            broadcast(destroyed_state, :target_cleared, %{
              player_id: target.id,
              target_id: nil,
              tick: destroyed_state.tick
            })
          end

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
    # An encounter ends on destruction. Legacy combat regression fixtures
    # alone opt into the automatic respawn behavior.
    due_tick =
      if state.auto_respawn? and
           not String.starts_with?(npc.npc_type_id, ["solar-dart-", "solar-scow-"]),
        do: state.tick + npc.respawn_delay_ticks, else: nil
    respawns =
      if is_integer(due_tick) do
        Map.put(state.respawns, npc.id,
          %{npc_type_id: npc.npc_type_id, spawn_index: npc.spawn_index, due_tick: due_tick})
      else
        state.respawns
      end

    {entities, cleared_entities} =
      Enum.reduce(state.entities, {%{}, []}, fn {entity_id, entity}, {entities, cleared} ->
        if entity.target_id == npc.id or entity.engaged_target_id == npc.id do
          updated = %{entity | target_id: nil, engaged_target_id: nil}
          {Map.put(entities, entity_id, updated), [entity | cleared]}
        else
          {Map.put(entities, entity_id, entity), cleared}
        end
      end)

    state = %{
      state
      | entities: entities,
        npcs: Map.delete(state.npcs, npc.id),
        respawns: respawns
    }

    Enum.each(cleared_entities, fn entity ->
      if not is_nil(entity.engaged_target_id) do
        broadcast(
          state,
          :combat_disengaged,
          disengagement_payload(entity, :target_destroyed, state.tick)
        )
      end

      if not is_nil(entity.target_id) do
        broadcast(state, :target_cleared, %{
          player_id: entity.id,
          target_id: nil,
          tick: state.tick
        })
      end
    end)

    broadcast(state, :entity_destroyed, %{
      entity: public_entity(npc),
      attacker_id: attacker_id,
      tick: state.tick,
      respawn_tick: due_tick
    })

    {state, Map.put(attack_payload, :respawn_tick, due_tick)}
  end

  defp activate_action(state, _entity, slot, nil) do
    payload = %{slot: slot, status: :empty, action: nil, tick: state.tick}
    {:reply, {:ok, payload}, state}
  end

  defp activate_action(
         state,
         entity,
         slot,
         %{type: :ammunition, activation_mode: :toggle} = action
       ) do
    case toggle_laser_fire(state, entity, action) do
      {new_state, {:error, reason}} ->
        {:reply, {:error, reason}, new_state}

      {new_state, engagement} ->
        {:reply,
         {:ok,
          %{
            slot: slot,
            status: if(engagement.active, do: :activated, else: :deactivated),
            action: action,
            engagement: engagement,
            tick: state.tick
          }}, new_state}
    end
  end

  defp activate_action(state, _entity, _slot, _action) do
    {:reply, {:error, :unsupported_action}, state}
  end

  defp toggle_laser_fire(state, %{engaged_target_id: nil} = entity, action) do
    with {:ok, target_id} <- selected_target(entity),
         {:ok, target} <- fetch_npc(state, target_id),
         true <- Combat.valid_target?(entity, target),
         :ok <- armed_weapon(entity) do
      engage_entity(state, entity, target, action)
    else
      false -> {state, {:error, :invalid_target}}
      {:error, reason} -> {state, {:error, reason}}
    end
  end

  defp toggle_laser_fire(state, entity, action) do
    updated_entity = %{entity | engaged_target_id: nil}
    new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}

    broadcast(
      new_state,
      :combat_disengaged,
      disengagement_payload(entity, :laser_toggled_off, state.tick)
    )

    {new_state,
     %{
       player_id: entity.id,
       target_id: entity.target_id,
       previous_target_id: entity.engaged_target_id,
       engaged_target_id: nil,
       action_id: action.id,
       active: false,
       changed: true,
       reason: :laser_toggled_off,
       tick: state.tick
     }}
  end

  defp engage_entity(state, entity, target, action) do
    changed? = entity.engaged_target_id != target.id
    updated_entity = %{entity | engaged_target_id: target.id}
    new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}

    payload = %{
      player_id: entity.id,
      target_id: target.id,
      engaged_target_id: target.id,
      action_id: action.id,
      active: true,
      changed: changed?,
      tick: state.tick
    }

    if changed?, do: broadcast(new_state, :combat_engaged, payload)
    {new_state, payload}
  end

  defp clear_player_combat(state, entity, reason) do
    updated_entity = %{entity | target_id: nil, engaged_target_id: nil}
    new_state = %{state | entities: Map.put(state.entities, entity.id, updated_entity)}

    if not is_nil(entity.engaged_target_id) do
      broadcast(new_state, :combat_disengaged, disengagement_payload(entity, reason, state.tick))
    end

    if not is_nil(entity.target_id) do
      broadcast(new_state, :target_cleared, %{
        player_id: entity.id,
        target_id: nil,
        tick: state.tick
      })
    end

    {new_state,
     %{
       player_id: entity.id,
       target_id: nil,
       previous_target_id: entity.engaged_target_id || entity.target_id,
       reason: reason,
       tick: state.tick
     }}
  end

  defp disengagement_payload(entity, reason, tick) do
    %{
      player_id: entity.id,
      target_id: nil,
      previous_target_id: entity.engaged_target_id,
      reason: reason,
      tick: tick
    }
  end

  defp engagement_error_reason(:target_not_found), do: :target_removed
  defp engagement_error_reason(:target_destroyed), do: :target_destroyed
  defp engagement_error_reason(:attacker_destroyed), do: :player_destroyed
  defp engagement_error_reason(_reason), do: :target_invalid

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

  # Only player ships carry a plotted route. NPC patrols retain the original
  # one-destination movement behavior and never read player-only struct fields.
  defp advance_entity(%Entity{} = entity, distance) do
    case Movement.advance(entity.position, entity.destination, distance) do
      {position, :moving} ->
        %{entity | position: position}

      {position, :arrived} ->
        case entity.route_waypoints do
          [next | remaining] ->
            %{entity | position: position, destination: next, route_waypoints: remaining}

          [] ->
            %{entity | position: position, destination: nil, navigation_mode: :manual}
        end
    end
  end

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

  # Merchant survival thresholds are intentionally explicit and
  # deterministic. They are V1 tuning, NOT reverse-engineered original
  # Space Rogue odds. Scows accelerate away once they have lost 20% of
  # their hull, and surrender at 35% remaining. Their original destination
  # is retained while evading; only surrender stops them.
  defp maybe_scow_survival(%NPCEntity{status: :alive, course: course} = npc)
       when is_map(course) do
    fraction = npc.hull / max(npc.max_hull, 1)

    cond do
      fraction <= 0.35 ->
        %{npc | state: :surrendered, destination: nil,
                speed: 0, target_id: nil}

      fraction <= 0.8 and npc.state == :cruise ->
        %{npc | state: :evade, speed: npc.speed * 1.5}

      true ->
        npc
    end
  end

  defp maybe_scow_survival(npc), do: npc

  defp tactical_course("scow", %{origin_id: from, destination_id: to}, spawn, map),
    do: CruiseRoute.project(from, to, spawn, map)

  defp tactical_course("dart", _route, _spawn, _map), do: {:ok, nil}
  defp tactical_course(_class, _route, _spawn, _map), do: {:error, :invalid_cruise_route}

  defp validate_tactical_ship_class(class) when class in ["dart", "scow"], do: :ok
  defp validate_tactical_ship_class(_class), do: {:error, :invalid_ship_class}

  # Player-initiated attacks on a neutral trader/patrol are not themselves
  # hits. A peaceful contact patrols until an authoritative weapon impact.
  # The first landed hit enables retaliation on subsequent world ticks.
  defp provoke_tactical_contacts(state, target_ids) do
    targets = MapSet.new(target_ids)

    changed =
      Map.new(state.solar_tactical, fn {pilot_id, encounter} ->
        updated =
          if MapSet.member?(targets, encounter.npc_id),
            do: Map.put(encounter, :provoked?, true),
            else: encounter
        {pilot_id, updated}
      end)

    %{state | solar_tactical: changed}
  end

  # Dynamic tactical opponents pursue only their owning pilot, and neutral
  # vessels do not acquire a target until they have taken a confirmed hit.
  defp tactical_targets(state, npc, entities) do
    owner =
      Enum.find(state.solar_tactical, fn {_id, encounter} ->
        encounter.npc_id == npc.id
      end)

    case owner do
      nil ->
        Map.values(entities)

      {_pilot_id, %{provoked?: false}} ->
        []

      {pilot_id, _encounter} ->
        case Map.fetch(entities, pilot_id) do
          {:ok, pilot} -> [pilot]
          :error -> []
        end
    end
  end

  # Spawn an opponent in front of the pilot where possible. On planetary
  # maps the server rejects positions inside the physical collision exclusion,
  # so a tactical encounter never conceals an invisible fatal planet.
  defp solar_tactical_position(definition, %Entity{} = ship) do
    direction = Orientation.forward(ship.orientation)
    {dx, dy} = {direction.x, direction.y}
    ship_pos = ship.position

    offsets = [
      {dx * 520.0, dy * 520.0},
      {-dy * 520.0, dx * 520.0},
      {-dx * 520.0, -dy * 520.0}
    ]

    candidate =
      Enum.find_value(offsets, fn {x, y} ->
        position = %Position{
          x: ship_pos.x + x,
          y: ship_pos.y + y,
          z: ship_pos.z + direction.z * 520.0
        }

        if safe_tactical_spawn?(definition, position), do: position
      end)

    if candidate, do: {:ok, candidate}, else: {:error, :no_spawn_position}
  end

  defp safe_tactical_spawn?(definition, %Position{} = position) do
    within_map? = match?({:ok, _}, Movement.destination(definition, position))

    clear_of_planet? =
      case definition.planet do
        %{center: center, exclusion_radius: exclusion} ->
          dx = position.x - center.x
          dy = position.y - center.y
          dz = position.z - center.z
          dx * dx + dy * dy + dz * dz > (exclusion + 150.0) * (exclusion + 150.0)

        _ ->
          true
      end

    within_map? and clear_of_planet?
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

  defp armed_weapon(%{damage: damage}) when is_number(damage) and damage > 0, do: :ok
  defp armed_weapon(_entity), do: {:error, :weapon_unarmed}

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

    valid_volume? = is_number(definition.altitude_min) and is_number(definition.altitude_max) and
                    definition.altitude_min < definition.altitude_max
    valid_spawn? = match?({:ok, _position}, Movement.destination(definition, definition.spawn))

    if not (valid_dimensions? and valid_identity? and valid_volume? and valid_spawn?) do
      raise ArgumentError, "invalid world map definition: #{inspect(definition)}"
    end
  end

  defp valid_join_entry?(_definition, nil), do: true

  defp valid_join_entry?(definition,
          %{position: position, attitude: %{yaw: yaw, pitch: pitch, roll: roll}})
       when is_number(yaw) and is_number(pitch) and is_number(roll) do
    Enum.all?([yaw, pitch, roll], fn angle ->
      abs(angle) < 10.0 and angle == angle
    end) and match?({:ok, _}, Movement.destination(definition, position))
  end

  defp valid_join_entry?(_definition, _entry), do: false

  defp public_state(state) do
    proximity_warnings =
      state.entities
      |> Enum.sort_by(fn {id, _entity} -> inspect(id) end)
      |> Enum.flat_map(fn {id, entity} ->
        if Combat.alive?(entity) do
          case PlanetaryProximity.warning(entity.position, state.definition) do
            nil -> []
            warning -> [Map.put(warning, :entity_id, id)]
          end
        else
          []
        end
      end)

    entities =
      (Map.values(state.entities) ++ Map.values(state.npcs))
      |> Enum.sort_by(fn entity -> {entity_sort_order(entity), to_string(entity.id)} end)
      |> Enum.map(&public_entity/1)

    %{
      map_id: state.definition.id,
      region_name: state.definition.name,
      planet_id: if(state.definition.planet,
        do: state.definition.planet.body_id, else: "earth"),
      tick: state.tick,
      tick_ms: state.tick_ms,
      planetary_warnings: proximity_warnings,
      boundaries: %{width: state.definition.width, height: state.definition.height},
      volume: %{altitude_min: state.definition.altitude_min,
                altitude_max: state.definition.altitude_max},
      entities: entities
    }
  end

  defp public_entity(%Entity{} = entity) do
    %{
      id: entity.id,
      kind: entity.kind,
      player_id: entity.player_id,
      position: public_position(entity.position),
      position_3d: position_3d(entity.position),
      destination: public_position(entity.destination),
      destination_3d: position_3d(entity.destination),
      route_waypoints_3d: Enum.map(entity.route_waypoints, &position_3d/1),
      navigation_mode: entity.navigation_mode,
      flight_mode: entity.flight_mode,
      throttle: entity.throttle,
      forward_speed: entity.cruise_speed,
      attitude: entity.attitude,
      orientation: entity.orientation || Orientation.from_angles(entity.attitude),
      angular_velocity: entity.angular_velocity,
      velocity: entity.velocity,
      route_waypoints: Enum.map(entity.route_waypoints, &public_position/1),
      speed: entity.speed,
      hull: entity.hull,
      max_hull: entity.max_hull,
      shields: entity.shields,
      max_shields: entity.max_shields,
      shield_absorption: entity.shield_absorption,
      damage: entity.damage,
      attack_range: entity.attack_range,
      attack_cooldown_ticks: entity.attack_cooldown_ticks,
      next_attack_tick: entity.next_attack_tick,
      target_id: entity.target_id,
      engaged_target_id: entity.engaged_target_id,
      status: entity.status
    }
  end

  defp public_entity(%NPCEntity{} = entity) do
    %{
      id: entity.id,
      kind: entity.kind,
      npc_type_id: entity.npc_type_id,
      ship_class: npc_ship_class(entity.npc_type_id),
      # The strategic endpoints, tactical heading and local destination
      # belong to the server. UI renderers never choose an NPC trajectory.
      course: if(entity.course, do: Map.take(entity.course,
        [:origin_id, :destination_id, :deflected?]), else: nil),
      angle: npc_course_angle(entity),
      display_name: entity.display_name,
      position: public_position(entity.position),
      position_3d: position_3d(entity.position),
      destination: public_position(entity.destination),
      destination_3d: position_3d(entity.destination),
      speed: entity.speed,
      hull: entity.hull,
      max_hull: entity.max_hull,
      shields: entity.shields,
      max_shields: entity.max_shields,
      shield_absorption: entity.shield_absorption,
      damage: entity.damage,
      attack_range: entity.attack_range,
      attack_cooldown_ticks: entity.attack_cooldown_ticks,
      next_attack_tick: entity.next_attack_tick,
      target_id: entity.target_id,
      state: entity.state,
      status: entity.status
    }
  end

  # Published NPC model class is authoritative server data, not guessed by
  # each browser or phone based solely on a generated instance ID.
  defp npc_course_angle(%NPCEntity{course: %{heading: %{x: x, y: y}}}),
    do: :math.atan2(y, x)

  defp npc_course_angle(%NPCEntity{position: p, destination: d}) when not is_nil(d),
    do: :math.atan2(d.y - p.y, d.x - p.x)

  defp npc_course_angle(_npc), do: 0.0

  defp npc_ship_class(type_id) when is_binary(type_id) do
    cond do
      type_id == "scow" or String.starts_with?(type_id, "solar-scow-") -> "scow"
      type_id == "dart" or String.starts_with?(type_id, "solar-dart-") -> "dart"
      true -> nil
    end
  end

  defp npc_ship_class(_type_id), do: nil

  defp public_position(nil), do: nil

  # Legacy XY snapshots remain stable for the atlas and earlier clients/tests.
  defp public_position(position), do: %{x: position.x, y: position.y}

  defp position_3d(nil), do: nil
  defp position_3d(position), do: %{x: position.x, y: position.y, z: position.z}

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
      next_attack_tick: attacker.next_attack_tick,
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
