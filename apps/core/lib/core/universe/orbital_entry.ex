defmodule Core.Universe.OrbitalEntry do
  @moduledoc """
  Server-owned planet-relative tactical regions and deterministic safe entries.

  SOL's compressed interplanetary coordinates only determine the direction of
  arrival. All orbital regions use local-kilometre positions and true mean
  planetary radii; never interpolate a compressed cruise distance as altitude.

  All playable bodies come from Core.Universe.Sol.planets/0, so registering
  another planet with a radius automatically enables this collision-ready
  region geometry. Future star systems can supply their own catalog and
  map-identifier namespace through the same region model.
  """

  alias Core.Universe.Sol
  alias Core.World.MapDefinition
  alias Core.World.Position

  @minimum_region_size 400_000
  @entry_distance_multiplier 1.861
  @exclusion_multiplier 1.08

  @spec map_id(String.t()) :: String.t() | nil
  def map_id(id) when is_binary(id) do
    if Sol.destination?(id), do: "sol:" <> id, else: nil
  end

  def map_id(_), do: nil

  @doc "Every registered planet gets its own map, including Earth."
  @spec planet_maps() :: [MapDefinition.t()]
  def planet_maps, do: Enum.map(Sol.planets(), &region_definition!/1)

  @spec center(String.t()) :: map() | nil
  def center(id) when is_binary(id) do
    case Sol.fetch(id) do
      {:ok, planet} ->
        if Sol.destination?(id) do
          geometry = geometry!(planet)
          geometry.center
        else
          nil
        end
      :error -> nil
    end
  end

  def center(_), do: nil

  @doc """
  The arrival side points toward the previous planet in compressed SOL space.
  All arrivals remain outside CAUTION and face inward. A small deterministic
  per-pilot angular offset prevents exact overlap on repeated voyages.
  """
  @spec entry(String.t() | nil, String.t(), term(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def entry(origin_id, destination_id, player_id, voyage_number \\ 0) do
    with {:ok, destination} <- Sol.game_position_km(destination_id),
         {:ok, radius} <- Sol.planet_radius_km(destination_id),
         %{} = planet_center <- center(destination_id) do
      source =
        case Sol.game_position_km(origin_id) do
          {:ok, position} when origin_id != destination_id -> position
          _ -> %{x: destination.x + 1.0, y: destination.y, z: 0.0}
        end

      dx = source.x - destination.x
      dy = source.y - destination.y
      bearing = :math.atan2(dy, dx)
      offset = (:erlang.phash2({player_id, voyage_number}, 201) - 100) / 1000.0
      angle = bearing + offset
      outward_x = :math.cos(angle)
      outward_y = :math.sin(angle)
      distance = radius * @entry_distance_multiplier
      position = %Position{
        x: planet_center.x + outward_x * distance,
        y: planet_center.y + outward_y * distance,
        z: 0.0
      }
      yaw = :math.atan2(-outward_x, outward_y)

      {:ok, %{
        map_id: map_id(destination_id),
        body_id: destination_id,
        source_id: origin_id,
        planet_center: planet_center,
        position: position,
        attitude: %{yaw: yaw, pitch: 0.0, roll: 0.0},
        entry_direction: %{x: outward_x, y: outward_y, z: 0.0}
      }}
    else
      _ -> {:error, :invalid_planet}
    end
  end

  defp region_definition!(planet) do
    geometry = geometry!(planet)
    radius = geometry.radius

    %MapDefinition{
      id: map_id(planet.id),
      name: planet.name <> " Orbital Region",
      width: geometry.size,
      height: geometry.size,
      altitude_min: -geometry.size / 2,
      altitude_max: geometry.size / 2,
      planet: %{
        body_id: planet.id,
        center: geometry.center,
        radius_km: radius,
        exclusion_radius: radius * @exclusion_multiplier
      },
      spawn: %Position{x: geometry.center.x + radius * @entry_distance_multiplier,
                       y: geometry.center.y, z: 0.0}
    }
  end

  defp geometry!(planet) do
    {:ok, radius} = Sol.planet_radius_km(planet.id)
    # Large future planets expand their map instead of putting safe arrival
    # positions beyond the tactical map bounds.
    diameter = ceil(radius * @entry_distance_multiplier * 2.6)
    size = max(@minimum_region_size, diameter)
    %{radius: radius, size: size,
      center: %{x: size / 2.0, y: size / 2.0, z: 0.0}}
  end
end
