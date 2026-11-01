defmodule Core.World.MovementTest do
  use ExUnit.Case, async: true

  alias Core.World.MapDefinition
  alias Core.World.Movement
  alias Core.World.Position

  test "accepts positions on map boundaries and rejects positions outside them" do
    map = MapDefinition.starting_map()

    assert {:ok, %Position{x: 0, y: 0}} = Movement.destination(map, {0, 0})

    assert {:ok, %Position{x: 20_000, y: 12_000}} =
             Movement.destination(map, %{x: 20_000, y: 12_000})

    assert {:error, :outside_map} = Movement.destination(map, {-1, 100})
    assert {:error, :outside_map} = Movement.destination(map, {100, 12_001})
    assert {:error, :invalid_destination} = Movement.destination(map, %{x: "100", y: 100})
  end

  test "advances linearly without overshooting the destination" do
    position = %Position{x: 0.0, y: 0.0}
    destination = %Position{x: 30.0, y: 40.0}

    assert {%Position{x: x, y: y}, :moving} = Movement.advance(position, destination, 10)
    assert_in_delta x, 6.0, 0.000_001
    assert_in_delta y, 8.0, 0.000_001

    assert {^destination, :arrived} = Movement.advance(position, destination, 100)
  end
end
