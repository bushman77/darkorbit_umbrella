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
    "sun" => %{id: "sun", name: "Sun", kind: :star, au: 0.0, phase_deg: 0},
    "mercury" => %{id: "mercury", name: "Mercury", kind: :planet, au: 0.387, phase_deg: 20},
    "venus" => %{id: "venus", name: "Venus", kind: :planet, au: 0.723, phase_deg: 69},
    "earth" => %{id: "earth", name: "Earth", kind: :planet, au: 1.0, phase_deg: 138},
    "mars" => %{id: "mars", name: "Mars", kind: :planet, au: 1.524, phase_deg: 218},
    "jupiter" => %{id: "jupiter", name: "Jupiter", kind: :planet, au: 5.203, phase_deg: 282},
    "saturn" => %{id: "saturn", name: "Saturn", kind: :planet, au: 9.582, phase_deg: 340},
    "uranus" => %{id: "uranus", name: "Uranus", kind: :planet, au: 19.201, phase_deg: 17},
    "neptune" => %{id: "neptune", name: "Neptune", kind: :planet, au: 30.047, phase_deg: 120},
    "pluto" => %{id: "pluto", name: "Pluto", kind: :dwarf_planet, au: 39.482, phase_deg: 226}
  }

  @type body :: %{
    id: String.t(), name: String.t(), kind: atom(), au: float(),
    phase_deg: non_neg_integer()
  }

  # Cruise travels 65,000 GAME-km each real second (below light speed). The
  # non-linear map compresses the outer system for practical play durations.
  @game_km_per_log_au 16_000_000.0
  @outer_compression_km_per_au 800_000.0
  @outer_threshold_au 10.0
  @cruise_speed_km_s 65_000.0
  @light_speed_km_s 299_792.458

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
