defmodule Core.World.StationInteriorTest do
  use ExUnit.Case, async: true
  alias Core.World.StationInterior, as: Room

  test "walk intents never set coordinates, movement stays within hangar" do
    pose = Room.initial()
    assert {:ok, input} = Room.controls(%{"forward" => 1, "strafe" => 0, "turn" => 0})
    moved = Room.step(pose, input, 0.1)
    assert_in_delta moved.z, 42.2, 0.0001
    assert moved.x == pose.x
    far = Enum.reduce(1..2_000, pose, fn _, acc -> Room.step(acc, input, 0.1) end)
    assert far.z == -74.0
    strafe = %{input | forward: 0.0, strafe: 1.0}
    far_right = Enum.reduce(1..2_000, pose,
      fn _, acc -> Room.step(acc, strafe, 0.1) end)
    assert far_right.x == 25.0
  end

  test "invalid client commands and tampered saves cannot teleport" do
    assert {:error, :invalid_station_controls} =
      Room.controls(%{"forward" => 50, "strafe" => 0, "turn" => 0})
    assert {:error, :invalid_station_look} = Room.look(%{"delta_yaw" => 500})
    assert :error == Room.from_saved(%{"room_id" => "secret", "x" => 0,
      "z" => 0, "yaw" => 0})
    assert :error == Room.from_saved(%{"room_id" => "main_hangar", "x" => 1000,
      "z" => 0, "yaw" => 0})
    stored = Room.dump(Room.initial())
    assert {:ok, original} = Room.from_saved(stored)
    assert original == Room.initial()
  end
end
