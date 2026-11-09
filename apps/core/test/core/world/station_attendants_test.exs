defmodule Core.World.StationAttendantsTest do
  use ExUnit.Case, async: true
  alias Core.World.{StationAttendants, StationInterior}

  @ship %{hull: 205, max_hull: 300, shields: 12, max_shields: 50}

  test "exactly six unique, named staff appear in the appropriate service rooms" do
    people = StationAttendants.public()
    assert length(people) == 6
    assert length(Enum.uniq(Enum.map(people, & &1.id))) == 6
    assert length(Enum.uniq(Enum.map(people, & &1.room_id))) == 6
    for npc <- people do
      assert is_binary(npc.name) and byte_size(npc.name) > 0
      assert is_binary(npc.role) and byte_size(npc.role) > 0
      assert StationInterior.room_at(npc.x, npc.z) == npc.room_id
      refute Map.has_key?(npc, :responses)
    end
  end

  test "dialogues are within each room's actual kiosk range and use fixed topics" do
    for npc <- StationAttendants.public() do
      position = %{room_id: npc.room_id, x: npc.x, z: npc.z}
      assert {:ok, %{name: name, topics: topics}} =
        StationAttendants.talk(position, @ship, npc.id, "greeting")
      assert name == npc.name
      assert length(topics) == 2
      for topic <- topics do
        assert {:ok, %{message: message}} =
          StationAttendants.talk(position, @ship, npc.id, topic.id)
        assert byte_size(message) > 20
      end
      assert {:error, :invalid_station_topic} =
        StationAttendants.talk(position, @ship, npc.id, "grant_credits")
      assert {:error, :station_attendant_out_of_range} =
        StationAttendants.talk(%{position | x: npc.x + 100}, @ship,
          npc.id, "greeting")
      assert {:error, :station_attendant_out_of_range} =
        StationAttendants.talk(%{position | room_id: "concourse"}, @ship,
          npc.id, "greeting")
    end
  end

  test "repair engineer reports actual parked ship condition without modifying it" do
    repair = Enum.find(StationAttendants.public(), &(&1.id == "repair"))
    pose = %{room_id: "repair_bay", x: repair.x, z: repair.z}
    assert {:ok, %{message: text}} =
      StationAttendants.talk(pose, @ship, "repair", "condition")
    assert text =~ "205/300"
    assert text =~ "12/50"
    assert text =~ "no repairs have been performed"
  end
end
