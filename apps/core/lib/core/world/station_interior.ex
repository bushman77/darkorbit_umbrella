defmodule Core.World.StationInterior do
  @moduledoc """
  Server-authoritative room topology for Space Nova's first starbase.

  Positions are shared Three.js X/Z coordinates. A pilot must enter through
  physically connected door openings; the client submits only movement axes.
  The ship stays docked until a separate server-authorized launch.
  """
  @walk_speed 14.0
  @turn_speed 1.8
  @entry_room "main_hangar"
  @pi :math.pi()

  # Central aisle -> rear airlock -> concourse; side portals connect individual
  # service rooms. Keep these bounds aligned to the locally rendered geometry.
  # Rects are {room_id, min_x, max_x, min_z, max_z}. Earlier rectangles win
  # at overlaps, making the room label stable at every threshold.
  @rooms [
    {"main_hangar", -25.0, 25.0, -81.0, 60.0},
    {"airlock", -7.0, 7.0, -106.0, -81.0},
    {"concourse", -33.0, 33.0, -185.0, -105.0},
    {"repair_bay", -62.0, -34.0, -147.0, -113.0},
    {"trade_exchange", 34.0, 62.0, -147.0, -113.0},
    {"outfitting", -62.0, -34.0, -185.0, -151.0},
    {"resupply", 34.0, 62.0, -185.0, -151.0},
    {"mission_office", -27.0, -3.0, -214.0, -187.0},
    {"communications", 3.0, 27.0, -214.0, -187.0},
    # Short door apertures. All are overlapping with both adjacent floors.
    {"repair_bay", -36.0, -31.0, -134.0, -124.0},
    {"trade_exchange", 31.0, 36.0, -134.0, -124.0},
    {"outfitting", -36.0, -31.0, -175.0, -165.0},
    {"resupply", 31.0, 36.0, -175.0, -165.0},
    {"mission_office", -21.0, -11.0, -189.0, -181.0},
    {"communications", 11.0, 21.0, -189.0, -181.0}
  ]

  @doc "Initial first-person position, facing the small hangar services door."
  def initial, do: %{room_id: @entry_room, x: 0.0, z: 43.0, yaw: 0.0}

  @doc "The room label must agree with authoritative walkable geometry."
  def valid_pose?(%{room_id: name, x: x, z: z, yaw: yaw})
      when is_binary(name) and is_number(x) and is_number(z) and
           is_number(yaw) do
    finite?(x) and finite?(z) and finite?(yaw) and
      abs(yaw) <= 2 * @pi and room_at(x, z) == name
  end
  def valid_pose?(_), do: false

  def from_saved(%{"room_id" => name, "x" => x, "z" => z, "yaw" => yaw}) do
    pose = %{room_id: name, x: x, z: z, yaw: yaw}
    if valid_pose?(pose), do: {:ok, pose}, else: :error
  end
  def from_saved(_), do: :error

  def dump(pose) do
    if valid_pose?(pose) do
      %{"room_id" => pose.room_id, "x" => pose.x, "z" => pose.z, "yaw" => pose.yaw}
    end
  end

  @doc "Resolve a coordinate to one recognized station room or reject it."
  def room_at(x, z) when is_number(x) and is_number(z) do
    if finite?(x) and finite?(z) do
      Enum.find_value(@rooms, fn {id, min_x, max_x, min_z, max_z} ->
        if x >= min_x and x <= max_x and z >= min_z and z <= max_z, do: id
      end)
    end
  end
  def room_at(_, _), do: nil

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

  def look(%{"delta_yaw" => change}) when is_number(change) do
    if finite?(change) and abs(change) <= 0.35,
      do: {:ok, change * 1.0},
      else: {:error, :invalid_station_look}
  end
  def look(_), do: {:error, :invalid_station_look}

  def rotate(pose, change) when is_number(change) do
    %{pose | yaw: wrap(pose.yaw + change)}
  end

  @doc """
  Move with swept substeps and axis sliding so even a long tick cannot cross
  an interior wall or enter a locked service area through its side.
  """
  def step(pose, input, elapsed) when is_number(elapsed) and elapsed > 0 do
    dt = min(elapsed, 0.2)
    yaw = wrap(pose.yaw + input.turn * @turn_speed * dt)
    magnitude = max(1.0, :math.sqrt(input.forward * input.forward +
      input.strafe * input.strafe))
    forward = input.forward / magnitude * @walk_speed * dt
    strafe = input.strafe / magnitude * @walk_speed * dt
    dx = :math.sin(yaw) * forward + :math.cos(yaw) * strafe
    dz = -:math.cos(yaw) * forward + :math.sin(yaw) * strafe

    # 0.35-unit swept subdivisions prevent jumping through thin walls and
    # preserve predictable collision when diagonal walking into corners.
    count = max(1, ceil(max(abs(dx), abs(dz)) / 0.35))
    {x, z} =
      Enum.reduce(1..count, {pose.x, pose.z}, fn _, {x, z} ->
        next_x = x + dx / count
        x = if room_at(next_x, z), do: next_x, else: x
        next_z = z + dz / count
        z = if room_at(x, next_z), do: next_z, else: z
        {x, z}
      end)

    %{pose | x: x, z: z, yaw: yaw, room_id: room_at(x, z) || pose.room_id}
  end

  defp wrap(value), do: :math.atan2(:math.sin(value), :math.cos(value))
  defp finite?(value), do: value == value and abs(value) < 1.0e10
end
