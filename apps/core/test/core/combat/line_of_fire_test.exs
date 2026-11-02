defmodule Core.Combat.LineOfFireTest do
  use ExUnit.Case, async: true

  alias Core.Combat.LineOfFire
  alias Core.World.FlightDynamics
  alias Core.World.Position

  @origin %Position{x: 1_000.0, y: 1_000.0, z: 0.0}
  defp npc(id, x, y, z \\ 0.0) do
    %{id: id, position: %Position{x: x, y: y, z: z},
      kind: :npc, status: :alive, hull: 100}
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
