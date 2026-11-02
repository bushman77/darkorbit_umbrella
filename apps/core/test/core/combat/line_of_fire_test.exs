defmodule Core.Combat.LineOfFireTest do
  use ExUnit.Case, async: true

  alias Core.Combat.LineOfFire
  alias Core.World.FlightDynamics
  alias Core.World.Orientation
  alias Core.World.Position

  @origin %Position{x: 1_000.0, y: 1_000.0, z: 0.0}
  defp npc(id, x, y, z \\ 0.0) do
    %{id: id, position: %Position{x: x, y: y, z: z},
      kind: :npc, status: :alive, hull: 100}
  end

  test "two real wing-mounted rays hit an enemy under the central sight" do
    enemy = npc("ahead", 1_000.0, 700.0)
    beams = LineOfFire.trace_pair(
      @origin, Orientation.identity(), [enemy], 720.0
    )

    assert length(beams) == 2
    assert Enum.map(beams, & &1.side) == [:left, :right]
    assert Enum.all?(beams, & &1.hit)
    assert Enum.all?(beams, &(&1.target_id == "ahead"))
    [left, right] = beams
    assert left.from.x < @origin.x
    assert right.from.x > @origin.x
    assert_in_delta left.from.y, right.from.y, 1.0e-8
    assert_in_delta left.from.z, right.from.z, 1.0e-8
    assert left.to.y > enemy.position.y
    assert right.to.y > enemy.position.y
    assert left.to.x < enemy.position.x
    assert right.to.x > enemy.position.x
  end

  test "each wing can independently hit a different target" do
    left_npc = npc("left", 1_000.0 - 1.75 / 0.06, 700.0, 1.3 / 0.06)
    right_npc = npc("right", 1_000.0 + 1.75 / 0.06, 700.0, 1.3 / 0.06)
    [left, right] =
      LineOfFire.trace_pair(@origin, Orientation.identity(), [right_npc, left_npc], 720.0)

    assert left.hit and right.hit
    assert left.target_id == "left"
    assert right.target_id == "right"
  end

  test "two distinct red rays miss targets behind or outside range" do
    enemies = [npc("behind", 1_000.0, 1_200.0),
               npc("far", 1_000.0, 100.0),
               npc("side", 1_300.0, 760.0)]
    shots = LineOfFire.trace_pair(@origin, Orientation.identity(), enemies, 720.0)
    assert length(shots) == 2
    assert Enum.all?(shots, &(not &1.hit))
    assert Enum.all?(shots, &(is_nil(&1.target_id)))
    assert Enum.all?(shots, &(&1.to.y < &1.from.y))
  end

  test "gun mounts and their rays rotate with the ship through yaw and roll" do
    east = Orientation.from_angles(%{yaw: :math.pi() / 2, pitch: 0.0, roll: 0.0})
    target = npc("east", 1_350.0, 1_000.0)
    east_beams = LineOfFire.trace_pair(@origin, east, [target], 720.0)
    assert Enum.all?(east_beams, & &1.hit)
    assert Enum.all?(east_beams, &(&1.to.x > &1.from.x))

    rolled = Orientation.from_angles(%{yaw: 0.0, pitch: 0.0, roll: :math.pi() / 2})
    [left, right] = LineOfFire.wing_muzzles(@origin, rolled)
    # After a 90-degree bank the two symmetric wing tips are separated in Z.
    assert abs(left.from.z - right.from.z) > 50
    assert_in_delta left.from.x, right.from.x, 1.0e-8
  end

  test "fires down the current nose with no selected target" do
    east = FlightDynamics.forward(%{yaw: :math.pi() / 2, pitch: 0.0})
    enemy = npc("east", 1_250.0, 1_000.0)
    assert {:hit, ^enemy, point} = LineOfFire.trace(@origin, east, [enemy], 720.0)
    assert point.x > @origin.x
    assert_in_delta point.y, @origin.y, 1.0e-7
  end

  test "ray behind, sideways or out of range misses" do
    north = FlightDynamics.forward(%{yaw: 0.0, pitch: 0.0})
    enemies = [npc("back", 1_000.0, 1_250.0),
               npc("side", 1_090.0, 800.0),
               npc("far", 1_000.0, 200.0)]
    assert {:miss, endpoint} = LineOfFire.trace(@origin, north, enemies, 720.0)
    assert_in_delta endpoint.y, 280.0, 1.0e-8
    assert_in_delta endpoint.x, 1_000.0, 1.0e-8
  end

  test "nearest living ship in beam wins even if a more distant target is locked" do
    north = FlightDynamics.forward(%{yaw: 0.0, pitch: 0.0})
    far = npc("far", 1_000.0, 500.0)
    near = npc("near", 1_000.0, 830.0)
    dead = %{npc("destroyed", 1_000.0, 910.0) | hull: 0, status: :destroyed}
    assert {:hit, ^near, point} =
      LineOfFire.trace(@origin, north, [far, dead, near], 720.0)
    assert_in_delta point.y, 870.0, 1.0e-8
  end

  test "3D pitch determines hit height independently of roll" do
    angle = :math.pi() / 4
    forward = FlightDynamics.forward(%{yaw: 0.0, pitch: angle, roll: 1.4})
    enemy = npc("up", 1_000.0, 800.0, 200.0)
    assert {:hit, ^enemy, impact} =
      LineOfFire.trace(@origin, forward, [enemy], 720.0)
    assert impact.z > 100.0

    horizontal = FlightDynamics.forward(%{yaw: 0.0, pitch: 0.0, roll: 1.4})
    assert {:miss, _} = LineOfFire.trace(@origin, horizontal, [enemy], 720.0)
  end
end
