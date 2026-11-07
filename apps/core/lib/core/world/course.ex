defmodule Core.World.Course do
  @moduledoc """
  Atomic validation for a bounded set of server-owned map waypoints.
  """

  alias Core.World.MapDefinition
  alias Core.World.Movement

  @max_waypoints 8

  def max_waypoints, do: @max_waypoints

  @spec plan(MapDefinition.t(), term()) ::
          {:ok, [Core.World.Position.t()]} | {:error, term()}
  def plan(%MapDefinition{} = map, points)
      when is_list(points) and length(points) > 0 and length(points) <= @max_waypoints do
    result =
      Enum.reduce_while(points, {:ok, []}, fn point, {:ok, collected} ->
        case Movement.destination(map, point) do
          {:ok, position} -> {:cont, {:ok, [position | collected]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, positions} -> {:ok, Enum.reverse(positions)}
      error -> error
    end
  end

  def plan(%MapDefinition{}, _points), do: {:error, :invalid_course}
end
