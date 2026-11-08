defmodule Core.World.GreenStarbaseDocking do
  @moduledoc """
  Server-owned bay-entry and launch geometry for the Green Starbase.
  Only the authenticated MapServer entity may pass these checks.
  """
  alias Core.Universe.GreenStarbase
  alias Core.World.{Entity, GreenStarbaseSafety, Position}

  @scale 0.06
  @maximum_speed 15.0
  # Automatic docking requires an actual stationary vessel. The manual
  # emergency dock request retains its older safe-speed tolerance.
  @automatic_stop_speed 0.5

  def inside_bay?(%Position{} = position) do
    origin = GreenStarbase.local_site()
    lx = (position.x - origin.x) * @scale
    ly = (position.z - origin.z) * @scale
    lz = (position.y - origin.y) * @scale
    abs(lx) <= 11.0 and abs(ly) <= 5.5 and lz >= -19.0 and lz <= 11.0 and
      GreenStarbaseSafety.open_approach?(position) and
      not GreenStarbaseSafety.inside?(position)
  end

  def ready?(%Entity{status: :destroyed}), do: {:error, :ship_destroyed}
  def ready?(%Entity{} = ship) do
    cond do
      not inside_bay?(ship.position) -> {:error, :outside_docking_bay}
      ship.destination != nil or ship.route_waypoints != [] or
          ship.navigation_mode != :manual -> {:error, :stop_navigation_first}
      abs(ship.throttle) > 0.001 or abs(ship.cruise_speed) > @maximum_speed or
          velocity_speed(ship.velocity) > @maximum_speed ->
        {:error, :reduce_speed_to_dock}
      ship.engaged_target_id != nil -> {:error, :disengage_combat_first}
      true -> :ok
    end
  end

  @doc "Stricter stationary check for the timed, automatic docking sequence."
  def auto_ready?(%Entity{} = ship) do
    with :ok <- ready?(ship) do
      if abs(ship.cruise_speed) <= @automatic_stop_speed and
           velocity_speed(ship.velocity) <= @automatic_stop_speed do
        :ok
      else
        {:error, :ship_still_moving}
      end
    end
  end

  def launch_position do
    mouth = GreenStarbase.bay_mouth()
    %Position{x: mouth.x, y: mouth.y - 350.0, z: mouth.z}
  end

  def launch_attitude, do: %{yaw: :math.pi(), pitch: 0.0, roll: 0.0}

  def park(%Entity{} = ship), do: %{ship |
    docked: true, destination: nil, target_id: nil, engaged_target_id: nil,
    route_waypoints: [], navigation_mode: :manual,
    throttle: 0.0, cruise_speed: 0.0,
    velocity: %{x: 0.0, y: 0.0, z: 0.0},
    angular_velocity: %{yaw: 0.0, pitch: 0.0, roll: 0.0},
    rotation_input: %{yaw: 0.0, pitch: 0.0, roll: 0.0}
  }

  defp velocity_speed(%{x: x, y: y, z: z}) when is_number(x) and
       is_number(y) and is_number(z),
       do: :math.sqrt(x * x + y * y + z * z)
  defp velocity_speed(_), do: 1.0e12
end
