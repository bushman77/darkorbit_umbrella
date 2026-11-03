defmodule Core.World.FlightDynamics do
  @moduledoc """
  Deterministic, server-owned manual spacecraft motion.

  Coordinate convention: X east, Y south, Z up. Heading zero points north
  (negative Y). Positive yaw turns right; positive pitch raises the nose.
  Cruise tracks a signed forward speed along the live nose direction with
  no lateral drift. Newtonian mode applies thrust along the live nose while
  preserving world-space velocity and momentum.
  """

  alias Core.World.Entity
  alias Core.World.MapDefinition
  alias Core.World.Orientation
  alias Core.World.Position

  # Tuned for deliberate ship handling rather than instant camera panning.
  # All rates are radians/sec, and accelerations are radians/sec^2.
  # At full input, pitch reaches 38 deg/s in ~0.48 s.
  @turn_limits %{
    yaw: %{speed: 44.0, acceleration: 95.0, braking: 145.0},
    pitch: %{speed: 38.0, acceleration: 80.0, braking: 135.0},
    roll: %{speed: 56.0, acceleration: 110.0, braking: 165.0}
  }
  # Captured mouse-look uses a faster *server-bounded* rotational response.
  # The legacy keyboard rate profile remains unchanged when mouse-look is off.
  @mouse_turn_limits %{
    yaw: %{speed: 100.0, acceleration: 280.0, braking: 360.0},
    pitch: %{speed: 88.0, acceleration: 240.0, braking: 320.0}
  }
  @input_expiry_ticks 10

  @spec controls(Entity.t(), map(), non_neg_integer()) ::
          {:ok, Entity.t()} | {:error, :invalid_flight_controls}
  def controls(%Entity{} = entity, input, tick) when is_map(input) do
    throttle = get(input, "throttle", entity.throttle)
    yaw = get(input, "yaw", 0.0)
    pitch = get(input, "pitch", 0.0)
    roll = get(input, "roll", 0.0)
    mode = get(input, "mode", entity.flight_mode)
    mouse_steering? = get(input, "mouse_steering", false)

    if valid_axis?(throttle) and valid_axis?(yaw) and valid_axis?(pitch) and
         valid_axis?(roll) and is_boolean(mouse_steering?) and
         mode in [:cruise, :newtonian, "cruise", "newtonian"] do
      mode = if mode in [:newtonian, "newtonian"], do: :newtonian, else: :cruise

      # A pilot switching from Newtonian to Cruise keeps the component of
      # their existing momentum along the CURRENT nose. Cruise assistance
      # cancels sideways drift from that point onward.
      cruise_speed =
        if mode == :cruise and entity.flight_mode != :cruise do
          dot(entity.velocity, forward(entity))
          |> clamp(-entity.speed * 1.0, entity.speed * 1.0)
        else
          entity.cruise_speed
        end

      {:ok,
       %{
         entity
         | throttle: throttle * 1.0,
           cruise_speed: cruise_speed,
           rotation_input: %{yaw: yaw * 1.0, pitch: pitch * 1.0, roll: roll * 1.0,
                             mouse_steering: mouse_steering?},
           flight_mode: mode,
           control_tick: tick,
           destination: nil,
           route_waypoints: [],
           navigation_mode: :manual
       }}
    else
      {:error, :invalid_flight_controls}
    end
  end

  def controls(%Entity{}, _input, _tick), do: {:error, :invalid_flight_controls}

  @spec step(Entity.t(), MapDefinition.t(), number(), non_neg_integer()) :: Entity.t()
  def step(%Entity{} = entity, %MapDefinition{} = map, dt, tick)
      when is_number(dt) and dt > 0 do
    input =
      if tick - entity.control_tick <= @input_expiry_ticks,
        do: entity.rotation_input,
        else: %{yaw: 0.0, pitch: 0.0, roll: 0.0}

    # Integrate angular velocity as state: held keys ramp up to a safe
    # maximum, released keys brake to zero, and the reverse key brakes
    # then builds speed in the opposite direction. The trapezoid prevents
    # even the first tick from jumping straight to the new angular rate.
    {attitude, angular_velocity} =
      Enum.reduce([:yaw, :pitch, :roll], {%{}, %{}}, fn axis, {angles, rates} ->
        old_rate = Map.fetch!(entity.angular_velocity, axis)
        limits =
          if Map.get(input, :mouse_steering, false) and axis in [:yaw, :pitch],
            do: Map.fetch!(@mouse_turn_limits, axis),
            else: Map.fetch!(@turn_limits, axis)

        next_rate = advance_angular_rate(old_rate, Map.fetch!(input, axis),
                                         limits, dt)
        angle = wrap_angle(Map.fetch!(entity.attitude, axis) +
                           (old_rate + next_rate) * 0.5 * dt)

        {Map.put(angles, axis, angle), Map.put(rates, axis, next_rate)}
      end)

    # Angles are retained as legacy telemetry. Physical rotation uses
    # quaternion increments in the CURRENT ship axes, not world axes.
    delta = Map.new([:yaw, :pitch, :roll], fn axis ->
      {axis, wrap_angle(Map.fetch!(attitude, axis) - Map.fetch!(entity.attitude, axis))}
    end)
    orientation = Orientation.rotate_local(
      entity.orientation || Orientation.from_angles(entity.attitude), delta
    )
    heading = Orientation.forward(orientation)
    # Cruise is an assisted target-speed controller: the throttle selects a
    # signed desired speed and the server integrates acceleration/braking over
    # simulation ticks. Newtonian mode instead applies physical thrust.
    cruise_acceleration = max(18.0, entity.speed * 0.75) * dt
    cruise_braking = max(28.0, entity.speed * 1.2) * dt
    thrust_acceleration = max(24.0, entity.speed * 1.5) * dt
    speed = entity.speed * 1.0
    {velocity, cruise_speed} =
      case entity.flight_mode do
        :cruise ->
          # Cruise speed is a scalar in ship-forward coordinates. Each tick
          # realigns the actual velocity vector with the LIVE attitude, not
          # with a stale world-space vector from before the pilot turned.
          # Smooth acceleration remains; only lateral drift is eliminated.
          target_speed = entity.throttle * speed
          braking? = abs(target_speed) < abs(entity.cruise_speed) or
                     entity.cruise_speed * target_speed < 0.0
          max_change = if braking?, do: cruise_braking, else: cruise_acceleration
          forward_speed = approach_scalar(entity.cruise_speed, target_speed, max_change)
          {scale(heading, forward_speed), forward_speed}

        :newtonian ->
          # In Newtonian flight turning alone never cancels existing momentum.
          # New thrust still accelerates in the current nose direction.
          velocity =
            entity.velocity
            |> add(scale(heading, entity.throttle * thrust_acceleration))
            |> limit(speed * 1.5)

          {velocity, entity.cruise_speed}
      end

    predicted = %Position{
      x: entity.position.x + velocity.x * dt,
      y: entity.position.y + velocity.y * dt,
      z: entity.position.z + velocity.z * dt
    }

    position = %Position{
      x: clamp(predicted.x, 0.0, map.width * 1.0),
      y: clamp(predicted.y, 0.0, map.height * 1.0),
      z: clamp(predicted.z, map.altitude_min * 1.0, map.altitude_max * 1.0)
    }

    # Boundaries absorb outward motion instead of allowing the player to
    # accumulate invisible velocity outside the sector.
    velocity = %{
      x: if(position.x == predicted.x, do: velocity.x, else: 0.0),
      y: if(position.y == predicted.y, do: velocity.y, else: 0.0),
      z: if(position.z == predicted.z, do: velocity.z, else: 0.0)
    }

    %{entity | position: position, velocity: velocity, cruise_speed: cruise_speed,
               attitude: attitude, orientation: orientation, angular_velocity: angular_velocity}
  end

  @spec forward(Entity.t() | map()) :: %{x: float(), y: float(), z: float()}
  def forward(%Entity{} = entity) do
    Orientation.forward(entity.orientation || Orientation.from_angles(entity.attitude))
  end

  # Retain static Euler input for legacy map and test fixtures.
  def forward(%{yaw: yaw, pitch: pitch}) do
    %{
      x: :math.sin(yaw) * :math.cos(pitch),
      y: -:math.cos(yaw) * :math.cos(pitch),
      z: :math.sin(pitch)
    }
  end

  defp advance_angular_rate(current, input, limits, dt) do
    desired = input * degrees_to_radians(limits.speed)
    # Brake faster when reversing than when speeding up, without an
    # instantaneous direction flip or a lingering uncontrolled turn.
    acceleration =
      if input == 0.0 or current * input < 0,
        do: limits.braking,
        else: limits.acceleration

    max_delta = degrees_to_radians(acceleration) * dt
    difference = desired - current
    next_rate = current + clamp(difference, -max_delta, max_delta)

    # Avoid subnormal leftovers when an axis reaches neutral.
    if abs(next_rate) < 1.0e-10, do: 0.0, else: next_rate
  end

  defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180.0

  defp get(map, key, default), do: Map.get(map, key, Map.get(map, String.to_atom(key), default))

  defp valid_axis?(n) when is_integer(n), do: n >= -1 and n <= 1
  defp valid_axis?(n) when is_float(n), do: n == n and n >= -1.0 and n <= 1.0
  defp valid_axis?(_), do: false

  defp add(a, b), do: %{x: a.x + b.x, y: a.y + b.y, z: a.z + b.z}
  defp scale(a, n), do: %{x: a.x * n, y: a.y * n, z: a.z * n}
  defp magnitude(a), do: :math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
  defp dot(a, b), do: a.x * b.x + a.y * b.y + a.z * b.z

  defp limit(vector, maximum) do
    distance = magnitude(vector)
    if distance > maximum and distance > 0, do: scale(vector, maximum / distance), else: vector
  end

  defp approach_scalar(from, to, max_delta) do
    from + clamp(to - from, -max_delta, max_delta)
  end

  defp wrap_angle(angle), do: :math.atan2(:math.sin(angle), :math.cos(angle))
  defp clamp(value, min_value, max_value), do: min(max_value, max(min_value, value))
end
