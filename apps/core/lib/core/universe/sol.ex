defmodule Core.Universe.Sol do
  @moduledoc """
  The authoritative catalog for the first Solar System navigation prototype.

  Mean orbital distances are in AU, never combat-map XY. Orbital phase,
  ephemerides and intercept mechanics have not been implemented. Travel
  durations are explicit game-time balancing values, not physical estimates.
  """

  @bodies %{
    "sun" => %{id: "sun", name: "Sun", kind: :star, au: 0.0},
    "mercury" => %{id: "mercury", name: "Mercury", kind: :planet, au: 0.387},
    "venus" => %{id: "venus", name: "Venus", kind: :planet, au: 0.723},
    "earth" => %{id: "earth", name: "Earth", kind: :planet, au: 1.0},
    "mars" => %{id: "mars", name: "Mars", kind: :planet, au: 1.524},
    "jupiter" => %{id: "jupiter", name: "Jupiter", kind: :planet, au: 5.203},
    "saturn" => %{id: "saturn", name: "Saturn", kind: :planet, au: 9.582},
    "uranus" => %{id: "uranus", name: "Uranus", kind: :planet, au: 19.201},
    "neptune" => %{id: "neptune", name: "Neptune", kind: :planet, au: 30.047},
    "pluto" => %{id: "pluto", name: "Pluto", kind: :dwarf_planet, au: 39.482}
  }

  @type body :: %{id: String.t(), name: String.t(), kind: atom(), au: float()}
  @spec fetch(term()) :: {:ok, body()} | :error
  def fetch(id) when is_binary(id), do: Map.fetch(@bodies, id)
  def fetch(_), do: :error

  @spec destination?(term()) :: boolean()
  def destination?(id) do
    match?({:ok, %{kind: kind}} when kind in [:planet, :dwarf_planet], fetch(id))
  end

  @spec all() :: [body()]
  def all do
    @bodies |> Map.values() |> Enum.sort_by(& &1.au)
  end

  @doc """
  Bounded *demo* travel duration from the difference in mean orbit radii,
  12-120 seconds, not actual interplanetary distance or physical flight time.
  """
  @spec travel_duration_ms(String.t(), String.t()) :: pos_integer()
  def travel_duration_ms(from_id, to_id) do
    {:ok, from} = fetch(from_id)
    {:ok, to} = fetch(to_id)
    round(min(120, max(12, 12 + abs(to.au - from.au) * 3))) * 1_000
  end
end
