defmodule Core.Universe.Traffic do
  @moduledoc """
  Deterministic, player-independent SOL traffic for the first living-universe
  slice. This is strategic game-km movement, never a tactical map spawn.

  Every traffic vessel has a cargo manifest, purpose, route and schedule.
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

  @doc """
  Persistent scheduled ships. Their routes/initial phases are world data, not
  entities spawned on demand when a player is nearby. Different launch times
  produce different encounter opportunities without a per-player RNG spawn.
  """
  @spec seed() :: %{String.t() => map()}
  def seed do
    routes = [
      # Preserve the original freighter and its published cargo/route.
      {"meridian-01", "Meridian-01", :commercial_freighter, :neutral,
       "earth", "mars", 0.0, :scheduled_delivery,
       %{"industrial_machinery" => 120}, %{"refined_minerals" => 85}},
      # Begins > 2M game-km from Earth, but is catchable mid Earth→Venus.
      {"vesper-02", "Vesper-02", :courier, :neutral,
       "earth", "venus", 0.22, :express_delivery,
       %{"medical_supplies" => 48}, %{"civilian_mail" => 120}},
      {"wayfinder-04", "Wayfinder-04", :survey_vessel, :neutral,
       "earth", "mars", 0.22, :scientific_survey,
       %{"survey_equipment" => 25}, %{"rock_samples" => 18}},
      {"sentinel-07", "Sentinel-07", :patrol, :neutral,
       "venus", "mercury", 0.40, :sector_patrol,
       %{"patrol_supplies" => 40}, %{"patrol_supplies" => 40}},
      {"aurora-12", "Aurora-12", :commercial_freighter, :neutral,
       "mars", "jupiter", 0.43, :scheduled_delivery,
       %{"spare_parts" => 72}, %{"rare_ores" => 26}},
      {"sable-18", "Sable-18", :independent_trader, :neutral,
       "jupiter", "saturn", 0.37, :trade_route,
       %{"hydrogen_cells" => 65}, %{"research_data" => 21}}
    ]

    Map.new(routes, fn
      {suffix, name, kind, disposition, from, to, progress, purpose, outbound, inbound} ->
        vessel = %{
          id: "traffic:sol:" <> suffix,
          call_sign: name,
          kind: kind,
          faction_id: "independent",
          disposition: disposition,
          purpose: purpose,
          state: :in_transit,
          origin_id: from,
          destination_id: to,
          home_origin_id: from,
          home_destination_id: to,
          location_id: from,
          cargo: outbound,
          outbound_cargo: outbound,
          return_cargo: inbound,
          cruise_speed_km_s: @cruise_speed_km_s,
          voyage_number: 1,
          elapsed_ms: 0,
          dwell_remaining_ms: 0,
          distance_km: Sol.cruise_distance_km(from, to),
          position_km: position!(from)
        }
        vessel = Map.put(vessel, :duration_ms, duration(vessel))
        vessel = advance_vessel(vessel, trunc(vessel.duration_ms * progress))
        {vessel.id, vessel}
    end)
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
            message: vessel.call_sign <> ", independent service. " <>
              "Operating " <> Atom.to_string(vessel.purpose) <>
              " between " <> vessel.origin_id <> " and " <> vessel.destination_id <>
              ". No assistance requested."
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
      destination_id =
        if origin_id == vessel.home_destination_id,
          do: vessel.home_origin_id, else: vessel.home_destination_id
      cargo =
        if origin_id == vessel.home_destination_id,
          do: vessel.return_cargo, else: vessel.outbound_cargo

      outbound = %{vessel |
        state: :in_transit,
        origin_id: origin_id,
        destination_id: destination_id,
        cargo: cargo,
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
