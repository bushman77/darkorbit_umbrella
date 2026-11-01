defmodule Core.CombatTest do
  use ExUnit.Case, async: true

  alias Core.Combat
  alias Core.World.Position

  test "validates PvE targets, range, and deterministic cooldown ticks" do
    player = combatant(:player, :pilot, {0, 0}, damage: 40, next_attack_tick: 8)
    npc = combatant(:npc, "npc:one", {300, 400})

    assert Combat.valid_target?(player, npc)
    assert Combat.valid_target?(npc, player)
    refute Combat.valid_target?(player, %{player | id: :other})
    refute Combat.valid_target?(npc, %{npc | id: "npc:two"})

    assert Combat.in_range?(player, npc, 500)
    refute Combat.in_range?(player, npc, 499)
    refute Combat.cooldown_ready?(7, 8)
    assert Combat.cooldown_ready?(8, 8)
    assert {:error, :weapon_cooldown} = Combat.validate_attack(player, npc, 7)
    assert :ok = Combat.validate_attack(player, npc, 8)
    assert Combat.next_attack_tick(player, 8) == 15
  end

  test "applies shield absorption and hull overflow without negative values" do
    target = combatant(:npc, "npc:one", {0, 0}, hull: 500, shields: 80, absorption: 0.6)

    assert {damaged, result} = Combat.apply_damage(target, 100)

    assert result == %{
             requested_damage: 100,
             shield_damage: 60,
             hull_damage: 40,
             destroyed: false
           }

    assert damaged.shields == 20
    assert damaged.hull == 460

    assert {overflowed, overflow_result} = Combat.apply_damage(damaged, 100)
    assert overflow_result.shield_damage == 20
    assert overflow_result.hull_damage == 80
    assert overflowed.shields == 0
    assert overflowed.hull == 380

    assert {unchanged, negative_result} = Combat.apply_damage(overflowed, -10_000)
    assert negative_result.requested_damage == 0
    assert unchanged.shields == 0
    assert unchanged.hull == 380
  end

  test "marks zero-hull targets destroyed and refuses further attacks" do
    player = combatant(:player, :pilot, {0, 0}, damage: 500)
    npc = combatant(:npc, "npc:one", {1, 1}, hull: 100, shields: 0)

    assert {destroyed, %{destroyed: true, hull_damage: 100}} =
             Combat.apply_damage(npc, player.damage)

    assert destroyed.hull == 0
    assert destroyed.status == :destroyed
    refute Combat.alive?(destroyed)
    assert {:error, :target_destroyed} = Combat.validate_attack(player, destroyed, 0)
  end

  defp combatant(kind, id, {x, y}, opts \\ []) do
    %{
      id: id,
      kind: kind,
      position: %Position{x: x, y: y},
      destination: nil,
      target_id: nil,
      hull: Keyword.get(opts, :hull, 1_000),
      shields: Keyword.get(opts, :shields, 0),
      shield_absorption: Keyword.get(opts, :absorption, 0.0),
      damage: Keyword.get(opts, :damage, 40),
      attack_range: Keyword.get(opts, :attack_range, 500),
      attack_cooldown_ticks: Keyword.get(opts, :cooldown_ticks, 7),
      next_attack_tick: Keyword.get(opts, :next_attack_tick, 0),
      status: :alive
    }
  end
end
