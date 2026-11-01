defmodule Core.World.Movement do
  @moduledoc "Pure destination validation and deterministic linear movement."

  alias Core.World.MapDefinition
  alias Core.World.Position

  @spec destination(MapDefinition.t(), Position.t() | map() | {number(), number()}) ::
          {:ok, Position.t()} | {:error, :invalid_destination | :outside_map}
  def destination(%MapDefinition{} = map, input) do
    with {:ok, position} <- normalize(input),
         :ok <- validate_coordinates(position),
         :ok <- within_boundaries(map, position) do
      {:ok, position}
    end
  end

  @spec advance(Position.t(), Position.t(), number()) ::
          {Position.t(), :moving | :arrived}
  def advance(%Position{} = position, %Position{} = destination, distance)
      when is_number(distance) and distance >= 0 do
    delta_x = destination.x - position.x
    delta_y = destination.y - position.y
    remaining = :math.sqrt(delta_x * delta_x + delta_y * delta_y)

    cond do
      remaining == 0 ->
        {destination, :arrived}

      distance >= remaining ->
        {destination, :arrived}

      true ->
        ratio = distance / remaining

        {%Position{x: position.x + delta_x * ratio, y: position.y + delta_y * ratio}, :moving}
    end
  end

  defp normalize(%Position{} = position), do: {:ok, position}
  defp normalize({x, y}), do: {:ok, %Position{x: x, y: y}}
  defp normalize(%{x: x, y: y}), do: {:ok, %Position{x: x, y: y}}
  defp normalize(%{"x" => x, "y" => y}), do: {:ok, %Position{x: x, y: y}}
  defp normalize(_input), do: {:error, :invalid_destination}

  defp validate_coordinates(%Position{x: x, y: y}) do
    if finite_number?(x) and finite_number?(y),
      do: :ok,
      else: {:error, :invalid_destination}
  end

  defp finite_number?(value) when is_integer(value), do: true
  defp finite_number?(value) when is_float(value), do: value == value
  defp finite_number?(_value), do: false

  defp within_boundaries(map, position) do
    if position.x >= 0 and position.x <= map.width and position.y >= 0 and
         position.y <= map.height do
      :ok
    else
      {:error, :outside_map}
    end
  end
end
