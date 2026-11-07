defmodule Core.Universe.EncounterDirector do
  @moduledoc """
  Server-owned policy for genuine SOL traffic close passes.

  The director classifies only a vessel already found by
  `Core.Universe.Encounters`. It does not roll new ships, mutate traffic,
  stop a cruise, or create a tactical combat instance.

  Faction reputation is a server-owned input. Until a durable reputation
  ledger is connected, missing standings are neutral (0).
  """

  alias Core.Universe.{Encounters, Territory}

  @patrol_attention_at -25

  @type classification :: :neutral_flyby | :patrol_attention | :hostile_contact

  @doc """
  Resolve and classify the nearest real moving traffic contact.

  Classification is advisory for V1: a hostile contact or patrol attention
  does not yet imply an enforced inspection or physical tactical handoff.
  """
  @spec evaluate(map(), map(), map()) :: map() | nil
  def evaluate(traffic, voyage, reputations \\ %{}) do
    case Encounters.nearest(traffic, voyage) do
      nil ->
        nil

      encounter ->
        {:ok, jurisdiction} = Territory.classify(voyage.position_km)

        Map.put(
          encounter,
          :classification,
          classify(encounter, jurisdiction, reputations)
        )
    end
  end

  @doc """
  Hostile disposition takes precedence. A faction patrol requests attention
  only when the pilot is within that faction's ZOC and its standing is -25
  or worse. Other contacts remain observational, non-hostile flybys.

  Caller-supplied standings cannot change a contact's authoritative
  identity, route, position or disposition.
  """
  @spec classify(map(), map(), map()) :: classification()
  def classify(%{disposition: :hostile}, _jurisdiction, _reputations),
    do: :hostile_contact

  def classify(%{kind: :patrol, faction_id: faction_id}, %{claims: claims}, reputations)
      when is_binary(faction_id) and is_list(claims) do
    in_faction_zone? = Enum.any?(claims, &(&1.faction_id == faction_id))

    if in_faction_zone? and standing(reputations, faction_id) <= @patrol_attention_at do
      :patrol_attention
    else
      :neutral_flyby
    end
  end

  def classify(_encounter, _jurisdiction, _reputations), do: :neutral_flyby

  defp standing(reputations, faction_id) when is_map(reputations) do
    case Map.get(reputations, faction_id, 0) do
      value when is_integer(value) and value >= -100 and value <= 100 -> value
      _ -> 0
    end
  end

  defp standing(_reputations, _faction_id), do: 0
end
