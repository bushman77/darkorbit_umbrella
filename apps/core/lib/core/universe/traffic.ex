defmodule Core.Universe.Traffic do
  @moduledoc """
  Deterministic, player-independent SOL traffic for the first living-universe
  slice. This is strategic game-km movement, never a tactical map spawn.

  A named civilian freighter has a cargo manifest, purpose, route and schedule.
  It continues traveling and docking without connected pilots. Sensor contacts
  and hails are derived from server-owned positions; players do not create or
  steer the freighter by encountering it.

  State currently survives player disconnects and tactical sessions while the
  supervised world runs. Database persistence across server restarts and
  tactical encounter instancing are explicitly later milestones.
  """

  alias Core.Universe.Sol

  @sensor_radius_km 2_000_000.0
  @dock_ms 45_000
  @cruise_speed_km_s 42_000.0
  @freighter_id "traffic:sol:meridian-01"

  @spec seed() :: %{String.t() => map()}
  def seed do
    vessel = %{
      id: @freighter_id,
      call_sign: "Meridian-01",
      kind: :commercial_freighter,
      faction_id: "independent",
      disposition: :neutral,
      purpose: :scheduled_delivery,
      state: :in_transit,
      origin_id: "earth",
      destination_id: "mars",
      location_id: "earth",
      cargo: %{"industrial_machinery" => 120},
      cruise_speed_km_s: @cruise_speed_km_s,
      voyage_number: 1,
      elapsed_ms: 0,
      dwell_remaining_ms: 0,
      distance_km: Sol.cruise_distance_km("earth", "mars"),
      position_km: position!("earth")
    }

    %{vessel.id => Map.put(vessel, :duration_ms, duration(vessel))}
  end

  @spec advance(map(), non_neg_integer()) :: map()
  def advance(ships, elapsed_ms)
      when is_map(ships) and is_integer(elapsed_ms) and elapsed_ms >= 0 do
    Map.new(ships, fn {id, vessel} -> {id, advance_vessel(vessel, elapsed_ms)} end)
  end

  @doc """
  Public sensor contacts at an authoritative SOL game-km position. Cargo and
  private details are only returned by hailing an in-range ship.
  """
  @spec contacts(map(), map()) :: [map()]
  def contacts(ships, position) when is_map(ships) and is_map(position) do
    ships
    |> Map.values()
    |> Enum.flat_map(fn vessel ->
      distance = distance(vessel.position_km, position)

      if distance <= @sensor_radius_km do
        [%{
          id: vessel.id,
          call_sign: vessel.call_sign,
          kind: vessel.kind,
          disposition: vessel.disposition,
          origin_id: vessel.origin_id,
          destination_id: vessel.destination_id,
          purpose: vessel.purpose,
          state: vessel.state,
          distance_km: distance,
          position_km: vessel.position_km,
          voyage_number: vessel.voyage_number
        }]
      else
        []
      end
    end)
    |> Enum.sort_by(&{&1.distance_km, &1.id})
  end

  @doc "In-range, read-only civilian comms. No cargo transfer or quest state yet."
  @spec hail(map(), map(), String.t()) :: {:ok, map()} | {:error, atom()}
  def hail(ships, position, id) when is_binary(id) and is_map(ships) do
    case Map.fetch(ships, id) do
      :error -> {:error, :unknown_contact}
      {:ok, vessel} ->
        if distance(vessel.position_km, position) <= @sensor_radius_km do
          {:ok, %{
            id: vessel.id,
            call_sign: vessel.call_sign,
            disposition: vessel.disposition,
            origin_id: vessel.origin_id,
            destination_id: vessel.destination_id,
            purpose: vessel.purpose,
            state: vessel.state,
            cargo: vessel.cargo,
            message: "Meridian-01, independent freight service. " <>
              "Scheduled cargo delivery in progress. No assistance requested."
          }}
        else
          {:error, :contact_out_of_range}
        end
    end
  end

  def hail(_ships, _position, _id), do: {:error, :unknown_contact}

  @spec sensor_radius_km() :: float()
  def sensor_radius_km, do: @sensor_radius_km

  defp advance_vessel(vessel, 0), do: vessel

  defp advance_vessel(%{state: :in_transit} = vessel, delta_ms) do
    remaining = max(0, vessel.duration_ms - vessel.elapsed_ms)
    used = min(remaining, delta_ms)
    elapsed = vessel.elapsed_ms + used

    if elapsed >= vessel.duration_ms do
      arrived = %{vessel |
        state: :docked,
        location_id: vessel.destination_id,
        position_km: position!(vessel.destination_id),
        elapsed_ms: vessel.duration_ms,
        dwell_remaining_ms: @dock_ms
      }
      advance_vessel(arrived, delta_ms - used)
    else
      progress = elapsed / vessel.duration_ms
      %{vessel | elapsed_ms: elapsed,
        position_km: Sol.interpolate_game_position(
          position!(vessel.origin_id), position!(vessel.destination_id), progress)}
    end
  end

  defp advance_vessel(%{state: :docked} = vessel, delta_ms) do
    used = min(delta_ms, vessel.dwell_remaining_ms)
    remaining = vessel.dwell_remaining_ms - used

    if remaining == 0 do
      origin_id = vessel.location_id
      destination_id = if origin_id == "mars", do: "earth", else: "mars"
      cargo = if origin_id == "mars",
        do: %{"refined_minerals" => 85}, else: %{"industrial_machinery" => 120}

      outbound = %{vessel |
        state: :in_transit,
        origin_id: origin_id,
        destination_id: destination_id,
        cargo: cargo,
        purpose: :scheduled_delivery,
        elapsed_ms: 0,
        dwell_remaining_ms: 0,
        voyage_number: vessel.voyage_number + 1,
        distance_km: Sol.cruise_distance_km(origin_id, destination_id),
        position_km: position!(origin_id)
      }
      outbound = Map.put(outbound, :duration_ms, duration(outbound))
      advance_vessel(outbound, delta_ms - used)
    else
      %{vessel | dwell_remaining_ms: remaining}
    end
  end

  defp duration(vessel) do
    max(1, ceil(vessel.distance_km / vessel.cruise_speed_km_s * 1_000))
  end

  defp position!(id) do
    {:ok, position} = Sol.game_position_km(id)
    position
  end

  defp distance(a, b) do
    :math.sqrt(:math.pow(a.x - b.x, 2) + :math.pow(a.y - b.y, 2) +
      :math.pow(a.z - b.z, 2))
  end
end
