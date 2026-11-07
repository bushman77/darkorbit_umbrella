defmodule Core.NPC.AI do
  @moduledoc "Pure, bounded NPC state transitions and deterministic patrol decisions."

  alias Core.Combat
  alias Core.NPC.Definition
  alias Core.NPC.Entity
  alias Core.World.MapDefinition
  alias Core.World.Position

  @type action :: {:attack, term()}

  @spec step(Entity.t(), [map()], Definition.t(), MapDefinition.t(), non_neg_integer()) ::
          {Entity.t(), [action()]}
  def step(%Entity{status: :destroyed} = npc, _players, _definition, _map, _tick) do
    {%{npc | state: :destroyed, destination: nil, target_id: nil}, []}
  end

  def step(%Entity{} = npc, players, %Definition{} = definition, %MapDefinition{} = map, tick) do
    target = acquire_target(npc, players, definition)

    case npc.state do
      :idle -> idle(npc, target, map, tick)
      :patrol -> patrol(npc, target, tick)
      :cruise -> cruise(npc, target, tick)
      :evade -> cruise(npc, target, tick)
      :surrendered -> {%{npc | destination: nil, target_id: nil}, []}
      :pursue -> engage_or_idle(npc, target, tick)
      :attack -> engage_or_idle(npc, target, tick)
      :destroyed -> {%{npc | status: :destroyed, destination: nil, target_id: nil}, []}
    end
  end

  # Merchant Scows have a server-owned origin/destination and keep flying
  # that course. A turret can defend the hull while still moving forward;
  # merely engaging the player never resets the lane into a square patrol.
  # Capture/surrender/flee doctrines are separate future captain decisions.
  defp cruise(npc, nil, _tick), do: {%{npc | target_id: nil}, []}

  defp cruise(npc, target, tick) do
    if Combat.in_range?(npc, target, npc.attack_range) do
      actions =
        if Combat.cooldown_ready?(tick, npc.next_attack_tick),
          do: [{:attack, target.id}], else: []

      {%{npc | target_id: target.id}, actions}
    else
      # The captain knows who fired but does not abandon the registered
      # trade route to chase that pilot outside turret range.
      {%{npc | target_id: target.id}, []}
    end
  end

  defp idle(npc, nil, map, _tick), do: start_patrol(npc, map)
  defp idle(npc, target, _map, tick), do: engage(npc, target, tick)

  defp patrol(%Entity{destination: nil} = npc, nil, _tick) do
    {%{npc | state: :idle, target_id: nil}, []}
  end

  defp patrol(npc, nil, _tick), do: {%{npc | target_id: nil}, []}
  defp patrol(npc, target, tick), do: engage(npc, target, tick)

  defp engage_or_idle(npc, nil, _tick) do
    {%{npc | state: :idle, target_id: nil, destination: nil}, []}
  end

  defp engage_or_idle(npc, target, tick), do: engage(npc, target, tick)

  defp engage(npc, target, tick) do
    if Combat.in_range?(npc, target, npc.attack_range) do
      actions =
        if Combat.cooldown_ready?(tick, npc.next_attack_tick),
          do: [{:attack, target.id}],
          else: []

      {%{npc | state: :attack, target_id: target.id, destination: nil}, actions}
    else
      {%{npc | state: :pursue, target_id: target.id, destination: target.position}, []}
    end
  end

  defp acquire_target(npc, players, definition) do
    current =
      Enum.find(players, &(&1.id == npc.target_id and detectable?(npc, &1, definition, 1.25)))

    current ||
      players
      |> Enum.filter(&detectable?(npc, &1, definition, 1.0))
      |> Enum.min_by(&{distance_squared(npc.position, &1.position), inspect(&1.id)}, fn -> nil end)
  end

  defp detectable?(npc, player, definition, leash_multiplier) do
    Combat.alive?(player) and player.kind == :player and
      Combat.in_range?(npc, player, definition.detection_radius * leash_multiplier)
  end

  defp start_patrol(npc, map) do
    directions = [{1.0, 0.0}, {0.0, 1.0}, {-1.0, 0.0}, {0.0, -1.0}]
    direction_index = rem(npc.patrol_step + npc.spawn_index, length(directions))
    {direction_x, direction_y} = Enum.at(directions, direction_index)

    destination = %Position{
      x: clamp(npc.home_position.x + direction_x * npc.patrol_radius, 0.0, map.width * 1.0),
      y: clamp(npc.home_position.y + direction_y * npc.patrol_radius, 0.0, map.height * 1.0),
      z: npc.home_position.z
    }

    {%{
       npc
       | state: :patrol,
         target_id: nil,
         destination: destination,
         patrol_step: npc.patrol_step + 1
     }, []}
  end

  defp distance_squared(left, right) do
    delta_x = right.x - left.x
    delta_y = right.y - left.y
    delta_z = right.z - left.z
    delta_x * delta_x + delta_y * delta_y + delta_z * delta_z
  end

  defp clamp(value, minimum, maximum), do: min(maximum, max(minimum, value))
end
