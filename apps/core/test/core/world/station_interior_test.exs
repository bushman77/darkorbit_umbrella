defmodule Core.World.StationInteriorTest do
  use ExUnit.Case, async: true
  alias Core.World.StationInterior, as: Room

  defp walk(pose, axes, ticks) do
    {:ok, input} = Room.controls(Map.merge(%{
      "forward" => 0, "strafe" => 0, "turn" => 0
    }, axes))
    Enum.reduce(1..ticks, pose, fn _, current -> Room.step(current, input, 0.1) end)
  end

  test "14 units/s moves the docked pilot without accepting coordinates" do
    pose = Room.initial()
    moved = walk(pose, %{"forward" => 1}, 1)
    assert_in_delta moved.z, 41.6, 0.0001
    assert moved.x == pose.x
    assert moved.room_id == "main_hangar"

    # The main passage stays navigable, and walking farther without changing
    # X stops at the far concourse wall, rather than crossing into an office.
    far = walk(pose, %{"forward" => 1}, 500)
    assert far.room_id == "concourse"
    assert_in_delta far.z, -185.0, 0.36
    edge = walk(pose, %{"strafe" => 1}, 500)
    assert edge.room_id == "main_hangar"
    assert_in_delta edge.x, 25.0, 0.36
  end

  test "the small rear hangar door leads through the airlock to the concourse" do
    pose = walk(Room.initial(), %{"forward" => 1}, 90)
    assert pose.room_id == "airlock"
    assert pose.z < -81
    concourse = walk(pose, %{"forward" => 1}, 20)
    assert concourse.room_id == "concourse"
    assert concourse.z < -106
    # Return through the SAME server corridor into the hangar.
    return = walk(concourse, %{"forward" => -1}, 120)
    assert return.room_id == "main_hangar"
  end

  test "off-axis approaches collide with the hangar wall, not teleport" do
    off_axis = %{Room.initial() | x: 20.0}
    stuck = walk(off_axis, %{"forward" => 1}, 120)
    assert stuck.room_id == "main_hangar"
    assert_in_delta stuck.z, -81.0, 0.36
    assert Room.room_at(25.0, -87.0) == nil
  end

  test "six service rooms are accessible only through their specific doors" do
    # Construct safe verified positions on the concourse; all movement still
    # passes through the server collision/portal logic.
    for {name, x, z, strafe} <- [
      {"repair_bay", -31.0, -129.0, -1},
      {"trade_exchange", 31.0, -129.0, 1},
      {"outfitting", -31.0, -170.0, -1},
      {"resupply", 31.0, -170.0, 1}
    ] do
      origin = %{room_id: "concourse", x: x, z: z, yaw: 0.0}
      assert Room.valid_pose?(origin)
      reached = walk(origin, %{"strafe" => strafe}, 6)
      assert reached.room_id == name
    end

    for {name, x} <- [{"mission_office", -16.0}, {"communications", 16.0}] do
      origin = %{room_id: "concourse", x: x, z: -183.0, yaw: 0.0}
      reached = walk(origin, %{"forward" => 1}, 9)
      assert reached.room_id == name
      assert reached.z < -187
    end

    # A concourse wall outside a doorway cannot be crossed.
    blocked = walk(%{room_id: "concourse", x: -31.0, z: -143.0, yaw: 0.0},
      %{"strafe" => -1}, 100)
    assert blocked.room_id == "concourse"
    assert_in_delta blocked.x, -33.0, 0.36
  end

  test "invalid commands and forged saved locations do not teleport" do
    assert {:error, :invalid_station_controls} =
      Room.controls(%{"forward" => 50, "strafe" => 0, "turn" => 0})
    assert {:error, :invalid_station_look} = Room.look(%{"delta_yaw" => 500})
    assert :error == Room.from_saved(%{
      "room_id" => "locked_reactor", "x" => 0, "z" => -180, "yaw" => 0
    })
    assert :error == Room.from_saved(%{
      "room_id" => "trade_exchange", "x" => 0, "z" => -129, "yaw" => 0
    })
    assert :error == Room.from_saved(%{
      "room_id" => "main_hangar", "x" => 1_000, "z" => 0, "yaw" => 0
    })
    for pose <- [Room.initial(),
        %{room_id: "concourse", x: 4.0, z: -140.0, yaw: 0.8},
        %{room_id: "mission_office", x: -16.0, z: -200.0, yaw: 1.1}] do
      assert Room.valid_pose?(pose)
      assert {:ok, ^pose} = pose |> Room.dump() |> Room.from_saved()
    end
  end
end
