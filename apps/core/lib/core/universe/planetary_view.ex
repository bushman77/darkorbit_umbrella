defmodule Core.Universe.PlanetaryView do
  @moduledoc """
  Server-owned *visual staging* for celestial bodies in the cockpit.

  True planetary radii (km) are independent of SOL's compressed GAME-km
  travel distances and Sector 1-1 combat coordinates. V1 displays a clear,
  increasingly large approach during the final cruise, and stages an
  orbital-looking view when regional travel arrives. This is NOT a collision
  volume, physical orbital altitude, gravitational field or actual ship position.
  Real orbital entry and planetary-scale navigation will replace the staging.
  """

  @radii_km %{
    "mercury" => 2_439.7,
    "venus" => 6_051.8,
    "earth" => 6_371.0,
    "mars" => 3_389.5,
    "jupiter" => 69_911.0,
    "saturn" => 58_232.0,
    "uranus" => 25_362.0,
    "neptune" => 24_622.0,
    "pluto" => 1_188.3
  }

  # Dramatic but non-intersecting arrival view: a 65-degree wide sphere
  # within the standard 70-degree vertical cockpit camera.
  @arrival_diameter_deg 65.0
  @distant_diameter_deg 1.5

  @spec describe(map()) :: map() | nil
  def describe(%{status: :traveling, destination_id: id} = voyage) do
    with {:ok, radius} <- Map.fetch(@radii_km, id) do
      fraction =
        if voyage.travel_distance_km > 0 do
          min(1.0, max(0.0,
            voyage.distance_travelled_km / voyage.travel_distance_km))
        else
          0.0
        end

      # A presentation-only approach curve. The SOL travel model compresses
      # distances, so its game-km offsets cannot be used as physical altitude.
      # Never feed this visual distance back into physics or collisions.
      diameter = @distant_diameter_deg +
        (@arrival_diameter_deg - @distant_diameter_deg) *
          :math.pow(fraction, 4.0)

      visual(id, radius, diameter, :approach_preview)
    else
      :error -> nil
    end
  end

  def describe(%{status: :idle, location_id: id}) do
    with {:ok, radius} <- Map.fetch(@radii_km, id) do
      visual(id, radius, @arrival_diameter_deg, :orbital_preview)
      |> Map.put(:planet_center, Core.Universe.OrbitalEntry.center(id))
    else
      :error -> nil
    end
  end

  def describe(_), do: nil

  @spec radius_km(String.t()) :: {:ok, float()} | :error
  def radius_km(id), do: Map.fetch(@radii_km, id)

  defp visual(id, radius, diameter, stage) do
    angle = diameter * :math.pi() / 360.0

    %{
      body_id: id,
      radius_km: radius,
      visual_distance_km: radius / :math.sin(angle),
      angular_diameter_deg: diameter,
      stage: stage,
      visual_only: true
    }
  end
end
