defmodule Core.World.FlightDynamics do
  @moduledoc """
  Deterministic, server-owned manual spacecraft motion.

  Coordinate convention: X east, Y south, Z up. Heading zero points north
  (negative Y). Positive yaw turns right; positive pitch raises the nose.
  Cruise converges toward a signed commanded speed along the nose.
  Newtonian mode applies signed thrust along the nose and retains inertia.
  """

  alias Core.World.Entity
  alias Core.World.MapDefinition
  alias Core.World.Position

  @turn_rate :math.pi() / 2.5
  @pitch_limit :math.pi() / 2 - 0.01
  @input_expiry_ticks 10

  @spec controls(Entity.t(), map(), non_neg_integer()) ::
          {:ok, Entity.t()} | {:error, :invalid_flight_controls}
  def controls(%Entity{} = entity, input, tick) when is_map(input) do
    throttle = get(input, "throttle", entity.throttle)
    yaw = get(input, "yaw", 0.0)
    pitch = get(input, "pitch", 0.0)
    roll = get(input, "roll", 0.0)
    mode = get(input, "mode", entity.flight_mode)

    if valid_axis?(throttle) and valid_axis?(yaw) and valid_axis?(pitch) and
         valid_axis?(roll) and mode in [:cruise, :newtonian, "cruise", "newtonian"] do
      mode = if mode in [:newtonian, "newtonian"], do: :newtonian, else: :cruise

      {:ok,
       %{
         entity
         | throttle: throttle * 1.0,
           rotation_input: %{yaw: yaw * 1.0, pitch: pitch * 1.0, roll: roll * 1.0},
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

    attitude = %{
      yaw: wrap_angle(entity.attitude.yaw + input.yaw * @turn_rate * dt),
      pitch: clamp(entity.attitude.pitch + input.pitch * @turn_rate * dt,
                   -@pitch_limit, @pitch_limit),
      roll: wrap_angle(entity.attitude.roll + input.roll * @turn_rate * dt)
    }

    heading = forward(attitude)
    acceleration = max(24.0, entity.speed * 1.5) * dt
    speed = entity.speed * 1.0
    velocity =
      case entity.flight_mode do
        :cruise ->
          desired = scale(heading, entity.throttle * speed)
          approach(entity.velocity, desired, acceleration)

        :newtonian ->
          entity.velocity
          |> add(scale(heading, entity.throttle * acceleration))
          |> limit(speed * 1.5)
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

    %{entity | position: position, velocity: velocity, attitude: attitude}
  end

  @spec forward(map()) :: %{x: float(), y: float(), z: float()}
  def forward(%{yaw: yaw, pitch: pitch}) do
    %{
      x: :math.sin(yaw) * :math.cos(pitch),
      y: -:math.cos(yaw) * :math.cos(pitch),
      z: :math.sin(pitch)
    }
  end

  defp get(map, key, default), do: Map.get(map, key, Map.get(map, String.to_atom(key), default))

  defp valid_axis?(n) when is_integer(n), do: n >= -1 and n <= 1
  defp valid_axis?(n) when is_float(n), do: n == n and n >= -1.0 and n <= 1.0
  defp valid_axis?(_), do: false

  defp add(a, b), do: %{x: a.x + b.x, y: a.y + b.y, z: a.z + b.z}
  defp scale(a, n), do: %{x: a.x * n, y: a.y * n, z: a.z * n}
  defp magnitude(a), do: :math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

  defp limit(vector, maximum) do
    distance = magnitude(vector)
    if distance > maximum and distance > 0, do: scale(vector, maximum / distance), else: vector
  end

  defp approach(from, target, max_delta) do
    delta = %{x: target.x - from.x, y: target.y - from.y, z: target.z - from.z}
    add(from, limit(delta, max_delta))
  end

  defp wrap_angle(angle), do: :math.atan2(:math.sin(angle), :math.cos(angle))
  defp clamp(value, min_value, max_value), do: min(max_value, max(min_value, value))
end
