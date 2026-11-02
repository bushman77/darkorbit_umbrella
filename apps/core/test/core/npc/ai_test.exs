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

  defp player(id, x, y) do
    %{id: id, kind: :player, status: :alive, hull: 4_000, position: %Position{x: x, y: y}}
  end
end
