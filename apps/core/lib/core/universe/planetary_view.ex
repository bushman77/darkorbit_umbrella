defmodule Core.Universe.PlanetaryView do
  @moduledoc """
  Server-owned *visual staging* for celestial bodies in the cockpit.

  Physical radii are read from the canonical SOL catalogue. The interplanetary
  cruise approach remains visual-only because SOL distances are compressed;
  planetary region centres and collision boundaries are authoritative and
  tracked separately by the orbital simulation.
  """

  alias Core.Universe.Sol

  # Dramatic but non-intersecting arrival view: a 65-degree wide sphere
  # within the standard 70-degree vertical cockpit camera.
  @arrival_diameter_deg 65.0
  @distant_diameter_deg 1.5

  @spec describe(map()) :: map() | nil
  def describe(%{status: :traveling, destination_id: id} = voyage) do
    with {:ok, radius} <- Sol.planet_radius_km(id) do
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
    with {:ok, radius} <- Sol.planet_radius_km(id) do
      visual(id, radius, @arrival_diameter_deg, :orbital_preview)
      |> Map.put(:planet_center, Core.Universe.OrbitalEntry.center(id))
    else
      :error -> nil
    end
  end

  def describe(_), do: nil

  @spec radius_km(String.t()) :: {:ok, float()} | :error
  def radius_km(id), do: Sol.planet_radius_km(id)

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
