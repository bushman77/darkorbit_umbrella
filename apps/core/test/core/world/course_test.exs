defmodule Core.World.CourseTest do
  use ExUnit.Case, async: true

  alias Core.World.Course
  alias Core.World.MapDefinition

  test "validates and retains the order of up to eight waypoints" do
    map = MapDefinition.starting_map()
    assert Course.max_waypoints() == 8
    assert {:ok, route} = Course.plan(map, [%{x: 0, y: 0}, %{x: 500, y: 600}])
    assert Enum.map(route, &{&1.x, &1.y}) == [{0, 0}, {500, 600}]
  end

  test "rejects malformed, excessive, and out-of-bounds courses" do
    map = MapDefinition.starting_map()
    assert {:error, :invalid_course} = Course.plan(map, [])
    assert {:error, :invalid_course} = Course.plan(map, %{})
    assert {:error, :invalid_course} = Course.plan(map, List.duplicate(%{x: 3, y: 4}, 9))
    assert {:error, :outside_map} = Course.plan(map, [%{x: 300, y: 200}, %{x: 99_999, y: 200}])
    assert {:error, :invalid_destination} =
             Course.plan(map, [%{x: 300, y: 200}, %{x: "invalid", y: 200}])
  end
end
