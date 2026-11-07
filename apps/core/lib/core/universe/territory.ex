defmodule Core.Universe.Territory do
  @moduledoc """
  Pure, three-dimensional planetary Zone of Control (ZOC) geometry for SOL.

  A ZOC is a sphere centred on the authoritative game's SOL position for its
  planet. Membership is independent for every faction: two or more containing
  spheres mean contested space; none means unclaimed space. No combat, patrol,
  reputation or random encounter decisions are made here.

  The current Sol positions are fixed schematic game coordinates, not live
  ephemerides. Default radii are provisional: 53% of the centre-to-centre
  distance to the nearer adjacent orbital neighbour in the current SOL layout.
  This permits modest overlap where spheres intersect while leaving natural
  unclaimed gaps. Planet-by-planet radius overrides support later balancing.
  Neighbouring spheres are not guaranteed to overlap at every orbital phase.
  """

  alias Core.Universe.Sol

  @default_radius_fraction 0.53
  @max_coordinate 1.0e300

  @type point :: %{x: number(), y: number(), z: number()}
  @type zone :: %{
          id: String.t(),
          faction_id: String.t(),
          center_km: point(),
          radius_km: number()
        }

  @doc """
  Returns server-owned ZOC definitions in heliocentric AU order (no Sun ZOC).

  Options are server configuration only, never client-provided:
    * `:radius_fraction` — provisional radius as a fraction of the closest
      adjacent planet separation, default 0.53
    * `:radii_km` — per-planet overrides, e.g. %{"earth" => 4_000_000.0}

  All coordinates and radii use the same compressed SOL game-km frame as
  `Core.Universe.Navigation`. Do not mix these with local sector XYZ units.
  """
  @spec zones(keyword()) :: [zone()]
  def zones(opts \\ []) do
    fraction = Keyword.get(opts, :radius_fraction, @default_radius_fraction)
    overrides = Keyword.get(opts, :radii_km, %{})

    unless finite_number?(fraction) and fraction > 0 and fraction <= 1 do
      raise ArgumentError, "ZOC radius fraction must be in (0, 1]"
    end

    unless is_map(overrides) do
      raise ArgumentError, "ZOC radius overrides must be a map"
    end

    planets =
      Sol.all()
      |> Enum.filter(&Sol.destination?(&1.id))
      |> Enum.map(fn body ->
        {:ok, center} = Sol.game_position_km(body.id)
        %{id: body.id, center_km: center}
      end)

    planets
    |> Enum.with_index()
    |> Enum.map(fn {planet, index} ->
      neighbour_distances =
        planets
        |> Enum.with_index()
        |> Enum.filter(fn {_other, other_index} -> abs(index - other_index) == 1 end)
        |> Enum.map(fn {other, _} -> distance(planet.center_km, other.center_km) end)

      nearest = Enum.min(neighbour_distances)
      radius = Map.get(overrides, planet.id, nearest * fraction)

      unless finite_number?(radius) and radius > 0 do
        raise ArgumentError, "invalid ZOC radius for #{planet.id}"
      end

      %{
        id: planet.id,
        faction_id: planet.id,
        center_km: planet.center_km,
        radius_km: radius
      }
    end)
  end

  @doc """
  Classifies one server-owned SOL XYZ position.

  Returns `:unclaimed`, `:controlled`, or `:contested`. Claims are ordered by
  nearest normalized distance and contain a 0..1 influence value. The latter is
  a geometric weight, NOT a patrol probability or a reputation score.
  A point precisely on a sphere is inside that sphere.
  """
  @spec classify(term(), [zone()]) :: {:ok, map()} | {:error, atom()}
  def classify(position, zones \\ zones()) do
    with {:ok, point} <- normalize_point(position),
         {:ok, valid_zones} <- normalize_zones(zones) do
      claims =
        valid_zones
        |> Enum.flat_map(fn zone ->
          separation = distance(point, zone.center_km)

          if separation <= zone.radius_km do
            normalized = separation / zone.radius_km

            [
              %{
                zone_id: zone.id,
                faction_id: zone.faction_id,
                distance_km: separation,
                normalized_distance: normalized,
                influence: max(0.0, 1.0 - normalized)
              }
            ]
          else
            []
          end
        end)
        |> Enum.sort_by(&{&1.normalized_distance, &1.faction_id, &1.zone_id})

      status =
        case length(claims) do
          0 -> :unclaimed
          1 -> :controlled
          _ -> :contested
        end

      {:ok, %{status: status, claims: claims}}
    end
  end

  @doc """
  Returns every entry and exit along a straight segment in SOL game-km XYZ.

  Each event has `:entered` or `:exited`, a [0, 1] segment fraction and an
  exact interpolated position. Tangential contacts do not cross a boundary.
  Endpoint-only events are excluded to avoid duplicate events when consecutive
  travel segments share an endpoint. A zero-length segment has no crossings.
  """
  @spec crossings(term(), term(), [zone()]) :: {:ok, [map()]} | {:error, atom()}
  def crossings(from, to, zones \\ zones()) do
    with {:ok, start_point} <- normalize_point(from),
         {:ok, end_point} <- normalize_point(to),
         {:ok, valid_zones} <- normalize_zones(zones) do
      delta = subtract(end_point, start_point)
      squared_length = dot(delta, delta)

      events =
        if squared_length == 0 do
          []
        else
          valid_zones
          |> Enum.flat_map(&sphere_crossings(start_point, delta, squared_length, &1))
          |> Enum.sort_by(&{&1.fraction, &1.zone_id, &1.kind})
        end

      {:ok, events}
    end
  end

  defp sphere_crossings(start_point, delta, a, zone) do
    offset = subtract(start_point, zone.center_km)
    b = 2.0 * dot(offset, delta)
    c = dot(offset, offset) - zone.radius_km * zone.radius_km
    discriminant = b * b - 4.0 * a * c

    if discriminant <= 0 do
      []
    else
      root = :math.sqrt(discriminant)

      # Fraction is a scalar, not a one-element tuple. Tuple braces here
      # previously caused an arithmetic error when a route entered a ZOC.
      [{(-b - root) / (2.0 * a), :entered},
       {(-b + root) / (2.0 * a), :exited}]
      |> Enum.flat_map(fn {fraction, kind} ->
        if fraction > 0.0 and fraction < 1.0 do
          [
            %{
              zone_id: zone.id,
              faction_id: zone.faction_id,
              kind: kind,
              fraction: fraction,
              position_km: add(start_point, scale(delta, fraction))
            }
          ]
        else
          []
        end
      end)
    end
  end

  defp normalize_zones(zones) when is_list(zones) do
    result =
      Enum.reduce_while(zones, {:ok, []}, fn zone, {:ok, acc} ->
        case zone do
          %{id: id, faction_id: faction_id, center_km: center, radius_km: radius}
          when is_binary(id) and byte_size(id) > 0 and is_binary(faction_id) and
                 byte_size(faction_id) > 0 ->
            case normalize_point(center) do
              {:ok, point} ->
                if finite_number?(radius) and radius > 0 do
                  {:cont, {:ok, [%{zone | center_km: point} | acc]}}
                else
                  {:halt, {:error, :invalid_zone}}
                end

              _ ->
                {:halt, {:error, :invalid_zone}}
            end

          _ ->
            {:halt, {:error, :invalid_zone}}
        end
      end)

    case result do
      {:ok, valid} ->
        valid = Enum.reverse(valid)

        if length(Enum.uniq_by(valid, & &1.id)) == length(valid) do
          {:ok, valid}
        else
          {:error, :invalid_zone}
        end

      error ->
        error
    end
  end

  defp normalize_zones(_), do: {:error, :invalid_zone}

  defp normalize_point({x, y, z}), do: normalize_point(%{x: x, y: y, z: z})

  defp normalize_point(%{x: x, y: y, z: z}) do
    if finite_number?(x) and finite_number?(y) and finite_number?(z) do
      {:ok, %{x: x, y: y, z: z}}
    else
      {:error, :invalid_position}
    end
  end

  defp normalize_point(_), do: {:error, :invalid_position}

  defp finite_number?(value) when is_integer(value), do: abs(value) < @max_coordinate
  defp finite_number?(value) when is_float(value),
    do: value == value and abs(value) < @max_coordinate
  defp finite_number?(_), do: false

  defp subtract(a, b), do: %{x: a.x - b.x, y: a.y - b.y, z: a.z - b.z}
  defp add(a, b), do: %{x: a.x + b.x, y: a.y + b.y, z: a.z + b.z}
  defp scale(a, t), do: %{x: a.x * t, y: a.y * t, z: a.z * t}
  defp dot(a, b), do: a.x * b.x + a.y * b.y + a.z * b.z
  defp distance(a, b) do
    delta = subtract(a, b)
    :math.sqrt(dot(delta, delta))
  end
end
