defmodule Core.World.StationInterior do
  @moduledoc """
  Authoritative first-person movement within the static Green Starbase hangar.

  Coordinates are local Three.js scene X/Z units and a facing yaw. The
  desktop sends only bounded movement intentions, never coordinates; the
  Galaxy SBS viewer has no movement authority. Future rooms can extend the
  geometry model without changing the flight simulation.
  """
  @room "main_hangar"
  @walk_speed 8.0
  @turn_speed 1.8
  @xmin -25.0
  @xmax 25.0
  @zmin -74.0
  @zmax 60.0

  def initial, do: %{room_id: @room, x: 0.0, z: 43.0, yaw: 0.0}

  def valid_pose?(%{room_id: @room, x: x, z: z, yaw: yaw})
      when is_number(x) and is_number(z) and is_number(yaw),
      do: finite?(x) and finite?(z) and finite?(yaw) and
        x >= @xmin and x <= @xmax and z >= @zmin and z <= @zmax and
        abs(yaw) <= :math.pi() * 2
  def valid_pose?(_), do: false

  def from_saved(%{"room_id" => @room, "x" => x, "z" => z, "yaw" => yaw}) do
    pose = %{room_id: @room, x: x, z: z, yaw: yaw}
    if valid_pose?(pose), do: {:ok, pose}, else: :error
  end
  def from_saved(_), do: :error

  def dump(%{room_id: @room, x: x, z: z, yaw: yaw} = pose) do
    if valid_pose?(pose), do: %{
      "room_id" => @room, "x" => x, "z" => z, "yaw" => yaw
    }, else: nil
  end
  def dump(_), do: nil

  def controls(%{"forward" => forward, "strafe" => strafe, "turn" => turn})
      when is_number(forward) and is_number(strafe) and is_number(turn) do
    if Enum.all?([forward, strafe, turn],
        &(finite?(&1) and abs(&1) <= 1.0)) do
      {:ok, %{forward: forward * 1.0, strafe: strafe * 1.0, turn: turn * 1.0}}
    else
      {:error, :invalid_station_controls}
    end
  end
  def controls(_), do: {:error, :invalid_station_controls}

  def idle, do: %{forward: 0.0, strafe: 0.0, turn: 0.0}

  def look(%{"delta_yaw" => d}) when is_number(d) do
    if finite?(d) and abs(d) <= 0.35, do: {:ok, d * 1.0},
      else: {:error, :invalid_station_look}
  end
  def look(_), do: {:error, :invalid_station_look}

  def rotate(pose, change) when is_number(change) do
    %{pose | yaw: wrap(pose.yaw + change)}
  end

  def step(pose, input, elapsed) when is_number(elapsed) and elapsed > 0 do
    dt = min(elapsed, 0.2)
    yaw = wrap(pose.yaw + input.turn * @turn_speed * dt)
    magnitude = max(1.0, :math.sqrt(input.forward * input.forward +
      input.strafe * input.strafe))
    forward = input.forward / magnitude * @walk_speed * dt
    strafe = input.strafe / magnitude * @walk_speed * dt
    dx = :math.sin(yaw) * forward + :math.cos(yaw) * strafe
    dz = -:math.cos(yaw) * forward + :math.sin(yaw) * strafe
    # Physically bounded central aisle. The rear services airlock remains
    # closed until its own authoritative room transition is implemented.
    %{pose | x: clamp(pose.x + dx, @xmin, @xmax),
      z: clamp(pose.z + dz, @zmin, @zmax), yaw: yaw}
  end

  defp wrap(value), do: :math.atan2(:math.sin(value), :math.cos(value))
  defp clamp(value, low, high), do: min(high, max(low, value))
  defp finite?(value), do: value == value and abs(value) < 1.0e10
end
