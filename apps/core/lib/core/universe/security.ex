defmodule Core.Universe.Security do
  @moduledoc """
  Deterministic patrol presence and independent activity derived from SOL ZOCs.

  This is a pure policy layer, not an encounter generator. Every overlapping
  faction calculates its own patrol pressure and pilot-specific directive.
  Neither patrol pressure nor independent activity is a probability of combat,
  an interception check, or an assertion that an NPC has spawned.

  All inputs are server-owned. The default per-faction reputation is 0
  (neutral) until a separate persistence system supplies real standings.
  """

  alias Core.Factions
  alias Core.Universe.Territory

  @type assessment :: %{
          status: :controlled | :contested | :unclaimed,
          claims: [map()],
          patrols: [map()],
          independent_pressure: float()
        }

  @doc """
  Evaluate security at one SOL game-kilometre XYZ position.

  Server-only configuration:
    * `:zones`: authoritative ZOC definitions
    * `:reputations`: map from planetary faction ID to integer -100..100
    * `:wanted_factions`: map from faction ID to boolean warrant flag
    * `:security_strength`: map of faction IDs to 0..1 patrol capacity
    * `:shipping_lane_density`: local 0..1 shipping-lane activity

  Pressure is a relative 0..1 balancing weight, not a per-tick random roll.
  """
  @spec assess(term(), keyword()) :: {:ok, assessment()} | {:error, atom()}
  def assess(position, opts \\ [])

  def assess(position, opts) when is_list(opts) do
    zones = Keyword.get(opts, :zones, Territory.zones())
    reputations = Keyword.get(opts, :reputations, %{})
    warrants = Keyword.get(opts, :wanted_factions, %{})
    strengths = Keyword.get(opts, :security_strength, %{})
    lane_density = Keyword.get(opts, :shipping_lane_density, 0.0)

    with :ok <- validate_reputations(reputations),
         :ok <- validate_warrants(warrants),
         :ok <- validate_strengths(strengths),
         :ok <- validate_lane_density(lane_density),
         {:ok, territory} <- Territory.classify(position, zones) do
      patrols =
        territory.claims
        |> Enum.map(fn claim ->
          {:ok, policy} =
            Factions.patrol_directive(
              Map.get(reputations, claim.faction_id, 0),
              wanted: Map.get(warrants, claim.faction_id, false)
            )

          radial_factor =
            0.05 + 0.95 * :math.pow(max(0.0, 1.0 - claim.normalized_distance), 2)

          traffic_factor = 0.7 + 0.3 * lane_density
          strength = Map.get(strengths, claim.faction_id, 1.0)

          %{
            faction_id: claim.faction_id,
            band: policy.band,
            directive: policy.directive,
            normalized_distance: claim.normalized_distance,
            pressure: clamp01(radial_factor * traffic_factor * strength)
          }
        end)
        |> Enum.sort_by(fn patrol -> {-patrol.pressure, patrol.faction_id} end)

      independent_pressure = independent_pressure(territory)

      {:ok,
       %{
         status: territory.status,
         claims: territory.claims,
         patrols: patrols,
         independent_pressure: independent_pressure
       }}
    end
  end

  def assess(_position, _opts), do: {:error, :invalid_security_options}

  defp independent_pressure(%{status: :unclaimed}), do: 0.7
  defp independent_pressure(%{status: :contested}), do: 0.35

  defp independent_pressure(%{status: :controlled, claims: [claim]}) do
    clamp01(0.08 + 0.22 * (1.0 - claim.influence))
  end

  defp validate_reputations(map) when is_map(map) do
    if Enum.all?(map, fn {id, score} ->
         Factions.exists?(id) and match?({:ok, _}, Factions.band(score))
       end) do
      :ok
    else
      {:error, :invalid_reputations}
    end
  end

  defp validate_reputations(_), do: {:error, :invalid_reputations}

  defp validate_warrants(map) when is_map(map) do
    if Enum.all?(map, fn {id, wanted} ->
         Factions.exists?(id) and is_boolean(wanted)
       end) do
      :ok
    else
      {:error, :invalid_wanted_factions}
    end
  end

  defp validate_warrants(_), do: {:error, :invalid_wanted_factions}

  defp validate_strengths(map) when is_map(map) do
    if Enum.all?(map, fn {id, strength} ->
         Factions.exists?(id) and fraction?(strength)
       end) do
      :ok
    else
      {:error, :invalid_security_strength}
    end
  end

  defp validate_strengths(_), do: {:error, :invalid_security_strength}

  defp validate_lane_density(density) do
    if fraction?(density), do: :ok, else: {:error, :invalid_shipping_lane_density}
  end

  defp fraction?(number) when is_number(number), do: number >= 0 and number <= 1
  defp fraction?(_), do: false

  defp clamp01(value), do: max(0.0, min(1.0, value))
end
