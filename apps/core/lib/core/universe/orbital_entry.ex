defmodule Core.Universe.OrbitalEntry do
  @moduledoc """
  Deterministic, server-authoritative entries into planetary tactical regions.

  The incoming direction is taken from the SOL voyage's *origin* and destination
  positions, not from client-supplied coordinates. Each planet owns a separate
  shared tactical map. Within these maps, coordinates are provisional local
  kilometres (not SOL's compressed long-range game-kilometres). Ships enter
  outside a planet-sized exclusion radius, facing toward the centre.

  This is a staging model, not Keplerian insertion, gravity, or atmosphere.
  """

  alias Core.Universe.Sol
  alias Core.World.MapDefinition
  alias Core.World.Position

  @center %{x: 200_000.0, y: 200_000.0, z: 0.0}
  @region_size 400_000
  @entry_distance_multiplier 1.861

  @spec map_id(String.t()) :: String.t() | nil
  def map_id("earth"), do: MapDefinition.starting_map_id()
  def map_id(id) when is_binary(id) do
    if Sol.destination?(id), do: "sol:" <> id, else: nil
  end
  def map_id(_), do: nil

  @spec planet_maps() :: [MapDefinition.t()]
  def planet_maps do
    Sol.all()
    |> Enum.filter(&(Sol.destination?(&1.id) and &1.id != "earth"))
    |> Enum.map(fn planet ->
      %MapDefinition{
        id: map_id(planet.id),
        name: planet.name <> " Orbital Region",
        width: @region_size,
        height: @region_size,
        altitude_min: -200_000,
        altitude_max: 200_000,
        spawn: %Position{x: @center.x + 15_000.0, y: @center.y, z: 0.0}
      }
    end)
  end

  @spec center(String.t()) :: map() | nil
  def center("earth"), do: %{x: 10_000.0, y: 6_000.0, z: 0.0}
  def center(id) when is_binary(id) do
    if Sol.destination?(id), do: @center, else: nil
  end
  def center(_), do: nil

  @doc """
  A reproducible, bounded entry point. Approaching from the west means
  spawning west of the world; from the east means east. Small deterministic
  angular staggering avoids piling all pilots on one exact spawn point.
  """
  @spec entry(String.t() | nil, String.t(), term(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def entry(origin_id, destination_id, player_id, voyage_number \\ 0) do
    with {:ok, destination} <- Sol.game_position_km(destination_id),
         {:ok, radius} <- Core.Universe.PlanetaryView.radius_km(destination_id),
         center when not is_nil(center) <- center(destination_id) do
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
      # Earth retains the historic 20k x 12k combat fixture until migrated.
      # Actual planetary regions use local km and a real-radius approach.
      distance = if destination_id == "earth", do: 3_600.0,
                   else: radius * @entry_distance_multiplier

      position = %Position{
        x: center.x + outward_x * distance,
        y: center.y + outward_y * distance,
        z: 0.0
      }

      # Map XY is scene XZ; the ship nose is -scene Z at yaw 0.
      # Point the bow at the planet centre on arrival.
      yaw = :math.atan2(-outward_x, outward_y)

      {:ok, %{
        map_id: map_id(destination_id),
        body_id: destination_id,
        source_id: origin_id,
        planet_center: center,
        position: position,
        attitude: %{yaw: yaw, pitch: 0.0, roll: 0.0},
        entry_direction: %{x: outward_x, y: outward_y, z: 0.0}
      }}
    else
      _ -> {:error, :invalid_planet}
    end
  end
end
