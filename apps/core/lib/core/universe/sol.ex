defmodule Core.Universe.Sol do
  @moduledoc """
  The authoritative catalog for the first Solar System navigation prototype.

  Mean orbital distances in AU are astronomical reference values, not actual
  in-game separations. To keep sublight travel practical in multiplayer, the
  world uses separate, compressed gameplay-kilometer coordinates.

  Reference phases are fixed schematic anchors shared with the initial Atlas.
  They are not live ephemerides or orbital transfer calculations; game kilometers
  are not physical Solar System distances. All ships use one real-time clock.
  """

  @bodies %{
    "sun" => %{id: "sun", name: "Sun", kind: :star, au: 0.0, radius_km: nil, phase_deg: 0},
    "mercury" => %{id: "mercury", name: "Mercury", kind: :planet, au: 0.387, radius_km: 2439.7, phase_deg: 20},
    "venus" => %{id: "venus", name: "Venus", kind: :planet, au: 0.723, radius_km: 6051.8, phase_deg: 69},
    "earth" => %{id: "earth", name: "Earth", kind: :planet, au: 1.0, radius_km: 6371.0, phase_deg: 138},
    "mars" => %{id: "mars", name: "Mars", kind: :planet, au: 1.524, radius_km: 3389.5, phase_deg: 218},
    "jupiter" => %{id: "jupiter", name: "Jupiter", kind: :planet, au: 5.203, radius_km: 69911.0, phase_deg: 282},
    "saturn" => %{id: "saturn", name: "Saturn", kind: :planet, au: 9.582, radius_km: 58232.0, phase_deg: 340},
    "uranus" => %{id: "uranus", name: "Uranus", kind: :planet, au: 19.201, radius_km: 25362.0, phase_deg: 17},
    "neptune" => %{id: "neptune", name: "Neptune", kind: :planet, au: 30.047, radius_km: 24622.0, phase_deg: 120},
    "pluto" => %{id: "pluto", name: "Pluto", kind: :dwarf_planet, au: 39.482, radius_km: 1188.3, phase_deg: 226}
  }

  @type point :: %{x: float(), y: float(), z: float()}
  @type body :: %{
    id: String.t(), name: String.t(), kind: atom(), au: float(),
    radius_km: float() | nil, phase_deg: non_neg_integer()
  }

  # Cruise travels 65,000 GAME-km each real second (below light speed). The
  # non-linear map compresses the outer system for practical play durations.
  @game_km_per_log_au 16_000_000.0
  @outer_compression_km_per_au 800_000.0
  @outer_threshold_au 10.0
  @cruise_speed_km_s 65_000.0
  @light_speed_km_s 299_792.458
  @maximum_waypoint_radius_km 200_000_000.0
  @maximum_waypoint_altitude_km 10_000_000.0
  @minimum_sun_clearance_km 1_000_000.0
  @planet_waypoint_clearance_km 100_000.0

  @spec cruise_speed_km_s() :: float()
  def cruise_speed_km_s, do: @cruise_speed_km_s

  @spec light_speed_km_s() :: float()
  def light_speed_km_s, do: @light_speed_km_s

  @spec fetch(term()) :: {:ok, body()} | :error
  def fetch(id) when is_binary(id), do: Map.fetch(@bodies, id)
  def fetch(_), do: :error

  @spec destination?(term()) :: boolean()
  def destination?(id) do
    match?({:ok, %{kind: kind}} when kind in [:planet, :dwarf_planet], fetch(id))
  end

  @spec all() :: [body()]
  def all, do: @bodies |> Map.values() |> Enum.sort_by(& &1.au)

  @doc "All registered SOL planets and dwarf planets with physical radii."
  @spec planets() :: [body()]
  def planets, do: all() |> Enum.filter(&destination?(&1.id))

  @spec planet_radius_km(String.t()) :: {:ok, float()} | :error
  def planet_radius_km(id) do
    case fetch(id) do
      {:ok, %{kind: kind, radius_km: radius}}
          when kind in [:planet, :dwarf_planet] and is_number(radius) and radius > 0 ->
        {:ok, radius * 1.0}
      _ -> :error
    end
  end

  @doc """
  Deterministic, compressed system travel coordinates, not combat coordinates
  or a live astronomical ephemeris.
  """
  @spec game_position_km(String.t()) :: {:ok, map()} | :error
  def game_position_km(id) do
    case fetch(id) do
      {:ok, body} ->
        radius = @game_km_per_log_au * :math.log(1.0 + body.au) +
          @outer_compression_km_per_au * max(0.0, body.au - @outer_threshold_au)
        phase = body.phase_deg * :math.pi() / 180.0
        {:ok, %{x: radius * :math.cos(phase),
                y: radius * :math.sin(phase), z: 0.0}}
      :error -> :error
    end
  end

  @doc """
  Validate a free destination in compressed SOL game kilometres, not AU or
  local cockpit units. Reject nonfinite values and celestial collisions.
  Named planetary targets still use safe orbital entry geometry.
  """
  @spec waypoint(term()) :: {:ok, point()} | {:error, :invalid_solar_waypoint}
  def waypoint(%{x: x, y: y, z: z}) do
    if Enum.all?([x, y, z], &finite_coordinate?/1) do
      point = %{x: x * 1.0, y: y * 1.0, z: z * 1.0}
      distance = :math.sqrt(point.x * point.x + point.y * point.y)
      clear_of_planets =
        Enum.all?(planets(), fn body ->
          {:ok, center} = game_position_km(body.id)
          dx = point.x - center.x
          dy = point.y - center.y
          dz = point.z - center.z
          dx * dx + dy * dy + dz * dz >
            :math.pow(body.radius_km + @planet_waypoint_clearance_km, 2)
        end)

      if distance <= @maximum_waypoint_radius_km and
           distance >= @minimum_sun_clearance_km and
           abs(point.z) <= @maximum_waypoint_altitude_km and clear_of_planets do
        {:ok, point}
      else
        {:error, :invalid_solar_waypoint}
      end
    else
      {:error, :invalid_solar_waypoint}
    end
  end

  def waypoint(%{"x" => x, "y" => y, "z" => z}),
    do: waypoint(%{x: x, y: y, z: z})

  def waypoint(_), do: {:error, :invalid_solar_waypoint}

  defp finite_coordinate?(value) when is_number(value),
    do: value == value and abs(value) < 1.0e300
  defp finite_coordinate?(_), do: false

  @spec cruise_distance_km(String.t(), String.t()) :: float()
  def cruise_distance_km(from_id, to_id) do
    {:ok, from} = game_position_km(from_id)
    {:ok, to} = game_position_km(to_id)
    :math.sqrt(:math.pow(to.x - from.x, 2) +
               :math.pow(to.y - from.y, 2) +
               :math.pow(to.z - from.z, 2))
  end

  @spec interpolate_game_position(map(), map(), number()) :: map()
  def interpolate_game_position(from, to, fraction) do
    t = min(1.0, max(0.0, fraction))
    %{x: from.x + (to.x - from.x) * t,
      y: from.y + (to.y - from.y) * t,
      z: from.z + (to.z - from.z) * t}
  end

  @doc "Shared real-time clock: drive speed times elapsed seconds, not time warp."
  @spec travel_duration_ms(String.t(), String.t()) :: pos_integer()
  def travel_duration_ms(from_id, to_id) do
    ceil(cruise_distance_km(from_id, to_id) / @cruise_speed_km_s) * 1_000
  end
end
