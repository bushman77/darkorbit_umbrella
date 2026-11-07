defmodule Core.Ships.ConditionTest do
  use ExUnit.Case, async: true

  alias Core.Ships.Condition

  test "initial condition uses ship capabilities" do
    assert {:ok, %{hull: 210, max_hull: 210, shields: 45, max_shields: 45,
                   status: :alive}} =
             Condition.initial(%{hit_points: 210, shields: 45})
  end

  test "damage accumulates without implicit healing" do
    {:ok, starting} = Condition.initial(%{hit_points: 210, shields: 45})
    damaged = %{starting | hull: 175, shields: 18}
    assert {:ok, ^damaged} = Condition.reconcile(starting, damaged)
    assert {:error, :unverified_repair} =
             Condition.reconcile(damaged, %{damaged | hull: 210})
    assert {:error, :unverified_repair} =
             Condition.reconcile(damaged, %{damaged | shields: 45})
    assert {:error, :capacity_mismatch} =
             Condition.reconcile(damaged, %{damaged | max_hull: 300})
  end

  test "loadout capacity changes clamp but never repair" do
    {:ok, initial} = Condition.initial(%{hit_points: 210, shields: 45})
    damaged = %{initial | hull: 175, shields: 18}
    assert {:ok, %{hull: 175, max_hull: 250, shields: 18, max_shields: 55}} =
             Condition.rebase(damaged, %{hit_points: 250, shields: 55})
    assert {:ok, %{hull: 100, max_hull: 100, shields: 10, max_shields: 10}} =
             Condition.rebase(damaged, %{hit_points: 100, shields: 10})
  end

  test "destruction persists without explicit respawn" do
    {:ok, initial} = Condition.initial(%{hit_points: 210, shields: 45})
    destroyed = %{initial | hull: 0, shields: 0, status: :destroyed}
    assert {:ok, ^destroyed} = Condition.reconcile(initial, destroyed)
    assert {:ok, %{status: :destroyed, hull: 0}} =
             Condition.rebase(destroyed, %{hit_points: 350, shields: 80})
    assert {:error, :invalid_ship_condition} =
             Condition.reconcile(destroyed, %{destroyed | hull: 1})
  end

  test "rejects malformed condition and invalid status transitions" do
    assert {:error, :invalid_ship_condition} =
             Condition.initial(%{hit_points: 0, shields: 45})
    assert {:error, :invalid_ship_condition} = Condition.validate(%{hull: "210"})
    {:ok, initial} = Condition.initial(%{hit_points: 210, shields: 45})
    surrendered = %{initial | hull: 60, shields: 0, status: :surrendered}
    assert {:ok, ^surrendered} = Condition.reconcile(initial, surrendered)
    assert {:error, :invalid_ship_status_transition} =
             Condition.reconcile(surrendered, %{surrendered | status: :alive})
  end
end
