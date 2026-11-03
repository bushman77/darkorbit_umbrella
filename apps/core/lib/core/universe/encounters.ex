defmodule Core.Universe.Encounters do
  @moduledoc """
  Non-hostile SOL flyby encounters from the existing shared traffic simulation.

  No proximity-based NPC spawning, no random player-specific ships and no
  position spoofing. Timing is emergent: a pilot's departure time, route and
  traffic's independently advancing timetable determine whether they cross.
  One encounter per traffic vessel voyage is announced to each pilot.
  Tactical interception and combat are separate future handoff milestones.
  """

  alias Core.Universe.Traffic

  @encounter_radius_km 650_000.0
  @departure_guard 0.05
  @arrival_guard 0.95

  @spec encounter_radius_km() :: float()
  def encounter_radius_km, do: @encounter_radius_km

  @spec nearest(map(), map()) :: map() | nil
  def nearest(ships, %{status: :traveling} = voyage) do
    progress =
      if voyage.travel_distance_km > 0,
        do: voyage.distance_travelled_km / voyage.travel_distance_km,
        else: 0.0

    if progress <= @departure_guard or progress >= @arrival_guard do
      nil
    else
      ships
      |> Traffic.contacts(voyage.position_km)
      |> Enum.filter(fn contact ->
        contact.state == :in_transit and
          contact.distance_km <= @encounter_radius_km
      end)
      |> Enum.sort_by(&{&1.distance_km, &1.id})
      |> List.first()
      |> to_encounter(voyage)
    end
  end

  def nearest(_ships, _voyage), do: nil

  defp to_encounter(nil, _voyage), do: nil

  defp to_encounter(contact, voyage) do
    %{
      id: "flyby:" <> contact.id <> ":" <> Integer.to_string(contact.voyage_number),
      contact_id: contact.id,
      call_sign: contact.call_sign,
      kind: contact.kind,
      faction_id: contact.faction_id,
      disposition: contact.disposition,
      purpose: contact.purpose,
      origin_id: contact.origin_id,
      destination_id: contact.destination_id,
      distance_km: contact.distance_km,
      relative_position_km: %{
        x: contact.position_km.x - voyage.position_km.x,
        y: contact.position_km.y - voyage.position_km.y,
        z: contact.position_km.z - voyage.position_km.z
      },
      mode: :strategic_flyby,
      communications_available: true
    }
  end
end
