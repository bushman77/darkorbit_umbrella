defmodule Core.World.OrientationTest do
  use ExUnit.Case, async: true

  alias Core.World.Orientation

  defp angle(degrees), do: degrees * :math.pi() / 180.0
  defp rotation(yaw, pitch, roll), do: %{yaw: yaw, pitch: pitch, roll: roll}

  test "identity faces north and right yaw faces east" do
    assert Orientation.forward(Orientation.identity()) == %{x: 0.0, y: -1.0, z: 0.0}
    nose = Orientation.from_angles(rotation(angle(90), 0.0, 0.0)) |> Orientation.forward()
    assert_in_delta nose.x, 1.0, 1.0e-10
    assert_in_delta nose.y, 0.0, 1.0e-10
    assert_in_delta nose.z, 0.0, 1.0e-10
  end

  test "pitch after yaw raises the nose along its current heading" do
    q = Orientation.rotate_local(Orientation.identity(), rotation(angle(90), 0.0, 0.0))
    nose = Orientation.rotate_local(q, rotation(0.0, angle(30), 0.0))
           |> Orientation.forward()
    assert_in_delta nose.x, :math.cos(angle(30)), 1.0e-10
    assert_in_delta nose.y, 0.0, 1.0e-10
    assert_in_delta nose.z, 0.5, 1.0e-10
  end

  test "pitch after roll is horizontal, not fixed to the world's up axis" do
    q = Orientation.rotate_local(Orientation.identity(), rotation(0.0, 0.0, angle(90)))
    nose = Orientation.rotate_local(q, rotation(0.0, angle(30), 0.0))
           |> Orientation.forward()
    assert_in_delta nose.x, -0.5, 1.0e-10
    assert_in_delta nose.y, -:math.cos(angle(30)), 1.0e-10
    assert_in_delta nose.z, 0.0, 1.0e-10
  end

  test "long rotation sequences remain normalized" do
    step = rotation(angle(0.7), angle(0.3), angle(0.4))
    q = Enum.reduce(1..1000, Orientation.identity(), fn _, acc ->
      Orientation.rotate_local(acc, step)
    end)
    assert_in_delta q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w, 1.0, 1.0e-10
  end
end
