defmodule Core.Universe.GreenStarbase do
  @moduledoc """
  The first independent SOL starbase, positioned on the server's compressed
  game-kilometre line between Earth and Mars.

  Unlike the nine planetary orbital refineries, this is a fixed interplanetary
  landmark. The Atlas charts its precise position as a validated waypoint.
  Docking permissions and station services remain later server milestones.
  """
  alias Core.Universe.Sol

  @id "sol:starbase:green"
  @name "Green Starbase"
  @local_site %{x: 12_000.0, y: 15_500.0, z: 0.0}
  @bay_mouth %{x: 12_000.0, y: 15_190.0, z: 0.0}
  @visual_radius_km 35_000.0

  def id, do: @id
  def name, do: @name
  def local_site, do: @local_site
  def bay_mouth, do: @bay_mouth

  @doc "Canonical cruise coordinate, independent of the cockpit's XYZ."
  def position_km do
    {:ok, earth} = Sol.game_position_km("earth")
    {:ok, mars} = Sol.game_position_km("mars")
    %{x: (earth.x + mars.x) / 2,
      y: (earth.y + mars.y) / 2,
      z: 0.0}
  end

  @doc "Public navigation landmark; no shared logistics or cargo inventories."
  def catalog do
    [%{id: @id, name: @name, kind: :starbase,
       position_km: position_km(), model: :green_pyramid_starbase_v1,
       site_3d: @local_site, bay_mouth_3d: @bay_mouth,
       status: :approach_only}]
  end

  @doc "Visual proximity only. This does not grant docking authorization."
  def nearby?(%{status: :idle, location_id: nil, position_km: position})
      when is_map(position) do
    center = position_km()
    :math.sqrt(:math.pow(position.x - center.x, 2) +
      :math.pow(position.y - center.y, 2) +
      :math.pow(position.z - center.z, 2)) <= @visual_radius_km
  end
  def nearby?(_), do: false
end
