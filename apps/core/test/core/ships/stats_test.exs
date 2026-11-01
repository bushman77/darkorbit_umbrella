defmodule Core.Ships.StatsTest do
  use ExUnit.Case, async: true

  alias Core.Equipment.Item
  alias Core.Ships.Ship
  alias Core.Ships.Stats

  test "returns base hit points, shields, speed, damage, and cargo for an empty loadout" do
    assert {:ok, stats} = Stats.calculate(1, %{lasers: [], generators: []})

    assert stats.hit_points == 4_000
    assert stats.shields == 0
    assert stats.speed == 320
    assert stats.damage == 40
    assert stats.cargo_capacity == 100
    assert stats.shield_absorption == 0.0
    assert stats.shield_regeneration == 0
  end

  test "derives damage and speed only from actually equipped items" do
    loadout = %{lasers: ["lf1"], generators: ["g3"]}

    assert {:ok, stats} = Stats.calculate(1, loadout)
    assert stats.damage == 80
    assert stats.speed == 327
    assert stats.shields == 0
  end

  test "derives shield capacity, weighted absorption, and regeneration" do
    loadout = %{lasers: ["lf2", nil], generators: ["sg1", "sg2"]}

    assert {:ok, stats} = Stats.calculate(2, loadout)
    assert stats.shields == 4_000
    assert_in_delta stats.shield_absorption, 0.4, 0.000_001
    assert stats.shield_regeneration == 17
  end

  test "keeps the two equipment configurations independent" do
    configurations = %{
      1 => %{lasers: ["lf1"], generators: ["g1"]},
      2 => %{lasers: ["lf4"], generators: ["sg2"]}
    }

    assert {:ok, %{1 => config_one, 2 => config_two}} =
             Stats.calculate_configurations(1, configurations)

    assert config_one.damage == 80
    assert config_one.speed == 322
    assert config_two.damage == 240
    assert config_two.shields == 2_000
  end

  test "requires both equipment configurations" do
    assert {:error, {:missing_configuration, 2}} =
             Stats.calculate_configurations(1, %{1 => %{lasers: [], generators: []}})
  end

  test "rejects equipment in locked ship slots" do
    assert {:error, {:slot_locked, :lasers, 1}} =
             Stats.calculate(1, %{lasers: [nil, "lf1"], generators: []})

    assert {:error, {:slot_locked, :generators, 1}} =
             Stats.calculate(1, %{lasers: [], generators: [nil, "g1"]})
  end

  test "rejects incompatible and unknown equipment" do
    assert {:error, {:incompatible_equipment, :lasers, 0, "g1"}} =
             Stats.calculate(1, %{lasers: ["g1"], generators: []})

    assert {:error, {:incompatible_equipment, :generators, 0, "lf1"}} =
             Stats.calculate(1, %{lasers: [], generators: ["lf1"]})

    assert {:error, {:unknown_equipment, "imaginary"}} =
             Stats.calculate(1, %{lasers: ["imaginary"], generators: []})
  end

  test "supports explicit catalogs for deterministic balancing experiments" do
    ships = [
      %Ship{
        id: 99,
        name: "Test ship",
        hit_points: 10,
        shields: 20,
        speed: 30,
        damage: 40,
        cargo_capacity: 50,
        laser_slots: 1,
        generator_slots: 0,
        damage_multiplier: 1.5
      }
    ]

    equipment = [
      %Item{id: "test-laser", name: "Test laser", category: :laser, damage: 20}
    ]

    assert {:ok, stats} =
             Stats.calculate(
               99,
               %{lasers: ["test-laser"], generators: []},
               ships: ships,
               equipment: equipment
             )

    assert stats.damage == 90
    assert stats.cargo_capacity == 50
  end

  test "accepts persisted loadout maps with string keys and fixed slot arrays" do
    loadout = %{
      "lasers" => %{"ship" => ["lf1" | List.duplicate(nil, 14)]},
      "generators" => %{"ship" => ["g1" | List.duplicate(nil, 14)]}
    }

    assert {:ok, stats} = Stats.calculate(1, loadout)
    assert stats.damage == 80
    assert stats.speed == 322
  end
end
