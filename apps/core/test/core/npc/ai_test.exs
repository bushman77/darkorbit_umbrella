defmodule Core.NPC.AITest do
  use ExUnit.Case, async: true

  alias Core.NPC.AI
  alias Core.NPC.Catalog
  alias Core.NPC.Entity
  alias Core.World.MapDefinition
  alias Core.World.Position

  setup do
    definition = Catalog.fetch!("dart")
    npc = Entity.spawn(definition, 0, 100)
    %{definition: definition, map: MapDefinition.starting_map(), npc: npc}
  end

  test "transitions deterministically from idle to local patrol", context do
    assert {first, []} = AI.step(context.npc, [], context.definition, context.map, 1)
    assert {second, []} = AI.step(context.npc, [], context.definition, context.map, 1)
    assert first == second
    assert first.state == :patrol
    assert first.destination == %Position{x: 1_720.0, y: 1_000.0}

    arrived = %{first | destination: nil}
    assert {%{state: :idle}, []} = AI.step(arrived, [], context.definition, context.map, 2)
  end

  test "detects, pursues, and attacks a live player", context do
    distant_player = player(:pilot, 1_000.0, 1_000.0)

    assert {pursuing, []} =
             AI.step(context.npc, [distant_player], context.definition, context.map, 1)

    assert pursuing.state == :pursue
    assert pursuing.target_id == :pilot
    assert pursuing.destination == distant_player.position

    nearby_player = player(:pilot, 1_400.0, 1_000.0)

    assert {attacking, [{:attack, :pilot}]} =
             AI.step(context.npc, [nearby_player], context.definition, context.map, 1)

    assert attacking.state == :attack
    assert attacking.destination == nil

    cooling_down = %{attacking | next_attack_tick: 10}

    assert {_attacking, []} =
             AI.step(cooling_down, [nearby_player], context.definition, context.map, 2)
  end

  test "returns to idle when a target disappears and preserves destroyed state", context do
    pursuing = %{context.npc | state: :pursue, target_id: :missing}

    assert {%{state: :idle, target_id: nil, destination: nil}, []} =
             AI.step(pursuing, [], context.definition, context.map, 2)

    destroyed = %{context.npc | status: :destroyed, state: :attack, target_id: :pilot}

    assert {%{state: :destroyed, target_id: nil, destination: nil}, []} =
             AI.step(destroyed, [], context.definition, context.map, 3)
  end

  test "a Scow keeps its assigned SOL course instead of drawing a square patrol", context do
    destination = %Position{x: 7_480.0, y: 1_000.0}
    route = %{origin_id: "venus", destination_id: "earth",
              heading: %{x: 1.0, y: 0.0, z: 0.0}}
    scow = %{context.npc | state: :cruise, destination: destination,
                             course: route}
    assert {cruising, []} =
      AI.step(scow, [], context.definition, context.map, 1)
    assert cruising.state == :cruise
    assert cruising.destination == destination
    assert cruising.patrol_step == scow.patrol_step

    # Even if attacked and the pilot is visible, the trader's defensive
    # turret can fire while the ship continues on the original heading.
    distant = player(:hunter, 2_150.0, 1_000.0)
    assert {aware, []} =
      AI.step(scow, [distant], context.definition, context.map, 2)
    assert aware.state == :cruise
    assert aware.target_id == :hunter
    assert aware.destination == destination

    close = player(:hunter, 1_520.0, 1_000.0)
    assert {retaliating, [{:attack, :hunter}]} =
      AI.step(scow, [close], context.definition, context.map, 3)
    assert retaliating.state == :cruise
    assert retaliating.destination == destination
  end

  defp player(id, x, y) do
    %{id: id, kind: :player, status: :alive, hull: 4_000, position: %Position{x: x, y: y}}
  end
end
