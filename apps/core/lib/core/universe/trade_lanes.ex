defmodule Core.Universe.TradeLanes do
  @moduledoc """
  Spatial SOL shipping corridors and approach traffic pressure.

  A destination does not affect the traffic field. The same point has the
  same pressure for a ship bound for Mars, an arbitrary waypoint, or nowhere.
  Direction is represented by real vessels' origin and destination IDs.

  This is a provisional SOL schedule, not a resource economy. Future terminal
  inventories and interstellar routes can replace the route catalog without
  changing proximity or encounter geometry.
  """

  alias Core.Universe.Sol

  # Intentional weighting: inner-system routes depart more often than the
  # outer-system frontier. Both directions are distinct real trade services.
  @departures [
    {"earth", "mars"}, {"venus", "earth"}, {"earth", "venus"},
    {"mars", "earth"}, {"earth", "mars"}, {"mercury", "venus"},
    {"venus", "earth"}, {"mars", "jupiter"}, {"earth", "mars"},
    {"jupiter", "mars"}, {"jupiter", "saturn"}, {"saturn", "jupiter"},
    {"saturn", "uranus"}, {"uranus", "neptune"}, {"neptune", "pluto"}
  ]

  @approach_radius_km 7_000_000.0
  @lane_radius_km 2_400_000.0

  @spec departures() :: [{String.t(), String.t()}]
  def departures, do: @departures

  @doc """
  Continuous 0..1 local traffic pressure, derived solely from the position.
  Planet approaches contribute up to 0.8; closeness to a genuine shipping
  corridor contributes up to 0.2. The field has no step boundaries.
  """
  @spec pressure(map()) :: float()
  def pressure(%{x: x, y: y, z: z}) when is_number(x) and is_number(y) and is_number(z) do
    planet =
      Sol.planets()
      |> Enum.map(fn body ->
        {:ok, at} = Sol.game_position_km(body.id)
        0.8 * fade(distance(%{x: x, y: y, z: z}, at), @approach_radius_km)
      end)
      |> Enum.max(fn -> 0.0 end)

    corridor =
      @departures
      |> Enum.uniq()
      |> Enum.map(fn {from, to} ->
        {:ok, start} = Sol.game_position_km(from)
        {:ok, stop} = Sol.game_position_km(to)
        0.2 * fade(segment_distance(%{x: x, y: y, z: z}, start, stop),
          @lane_radius_km)
      end)
      |> Enum.max(fn -> 0.0 end)

    min(1.0, planet + corridor)
  end

  def pressure(_), do: 0.0

  @spec band(map()) :: :quiet | :light | :moderate | :busy
  def band(position) do
    case pressure(position) do
      n when n >= 0.65 -> :busy
      n when n >= 0.3 -> :moderate
      n when n >= 0.08 -> :light
      _ -> :quiet
    end
  end

  defp fade(distance, limit) do
    weight = max(0.0, 1.0 - distance / limit)
    weight * weight
  end

  defp segment_distance(point, start, stop) do
    dx = stop.x - start.x
    dy = stop.y - start.y
    dz = stop.z - start.z
    length_sq = dx * dx + dy * dy + dz * dz
    fraction =
      if length_sq > 0.0 do
        ((point.x - start.x) * dx + (point.y - start.y) * dy +
           (point.z - start.z) * dz) / length_sq
      else
        0.0
      end

    t = min(1.0, max(0.0, fraction))
    distance(point, %{x: start.x + t * dx, y: start.y + t * dy,
      z: start.z + t * dz})
  end

  defp distance(a, b) do
    :math.sqrt(:math.pow(a.x - b.x, 2) + :math.pow(a.y - b.y, 2) +
      :math.pow(a.z - b.z, 2))
  end
end
