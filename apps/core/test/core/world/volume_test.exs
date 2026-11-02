defmodule Core.World.VolumeTest do
  use ExUnit.Case, async: true

  alias Core.Combat
  alias Core.World.MapDefinition
  alias Core.World.Movement
  alias Core.World.Position

  test "three-dimensional positions can move vertically and diagonally" do
    map = MapDefinition.starting_map()
    assert {:ok, %Position{z: 1_200}} =
             Movement.destination(map, %{x: 1_000, y: 1_000, z: 1_200})

    start = %Position{x: 0.0, y: 0.0, z: 0.0}
    goal = %Position{x: 30.0, y: 0.0, z: 40.0}
    assert {%Position{x: x, z: z}, :moving} = Movement.advance(start, goal, 25)
    assert_in_delta x, 15.0, 1.0e-6
    assert_in_delta z, 20.0, 1.0e-6
    assert {^goal, :arrived} = Movement.advance(start, goal, 50)
  end

  test "volume validates altitude while keeping old XY destination input" do
    map = MapDefinition.starting_map()
    assert {:ok, %Position{z: 0.0}} = Movement.destination(map, {1_000, 1_000})
    assert {:error, :outside_map} =
             Movement.destination(map, %{x: 1_000, y: 1_000, z: 3_001})
    assert {:error, :outside_map} =
             Movement.destination(map, %{x: 1_000, y: 1_000, z: -3_001})
    assert {:error, :invalid_destination} =
             Movement.destination(map, %{x: 1_000, y: 1_000, z: "invalid"})
  end

  test "combat range uses spatial distance rather than flat map proximity" do
    attacker = %{position: %Position{x: 100.0, y: 200.0, z: 0.0}}
    nearby = %{position: %Position{x: 100.0, y: 200.0, z: 100.0}}
    above = %{position: %Position{x: 100.0, y: 200.0, z: 900.0}}
    assert Combat.in_range?(attacker, nearby, 250.0)
    refute Combat.in_range?(attacker, above, 250.0)
  end
end
