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
  @max_procedural_contacts 32
  @procedural_lifetime_ms 900_000

  @doc """
  Persistent scheduled ships. Their routes/initial phases are world data, not
  entities spawned on demand when a player is nearby. Different launch times
  produce different encounter opportunities without a per-player RNG spawn.
  """
  @spec seed() :: %{String.t() => map()}
  def seed do
    routes = [
      # Preserve the original freighter and its published cargo/route.
      {"meridian-01", "Meridian-01", :commercial_freighter, :neutral, "independent",
       "earth", "mars", 0.0, :scheduled_delivery,
       %{"industrial_machinery" => 120}, %{"refined_minerals" => 85}},
      # Begins > 2M game-km from Earth, but is catchable mid Earth→Venus.
      {"vesper-02", "Vesper-02", :courier, :neutral, "independent",
       "earth", "venus", 0.22, :express_delivery,
       %{"medical_supplies" => 48}, %{"civilian_mail" => 120}},
      {"wayfinder-04", "Wayfinder-04", :survey_vessel, :neutral, "independent",
       "earth", "mars", 0.22, :scientific_survey,
       %{"survey_equipment" => 25}, %{"rock_samples" => 18}},
      {"sentinel-07", "Sentinel-07", :patrol, :neutral, "venus",
       "venus", "mercury", 0.40, :sector_patrol,
       %{"patrol_supplies" => 40}, %{"patrol_supplies" => 40}},
      {"aurora-12", "Aurora-12", :commercial_freighter, :neutral, "independent",
       "mars", "jupiter", 0.43, :scheduled_delivery,
       %{"spare_parts" => 72}, %{"rare_ores" => 26}},
      {"sable-18", "Sable-18", :independent_trader, :neutral, "independent",
       "jupiter", "saturn", 0.37, :trade_route,
       %{"hydrogen_cells" => 65}, %{"research_data" => 21}}
    ]

    Map.new(routes, fn
      {suffix, name, kind, disposition, faction_id, from, to, progress, purpose, outbound, inbound} ->
        vessel = %{
          id: "traffic:sol:" <> suffix,
          call_sign: name,
          kind: kind,
          ship_class: ship_class(kind),
          faction_id: faction_id,
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

  @doc """
  Introduce a real, shared traffic vessel on a converging interplanetary lane.

  The navigation server owns the serial, archetype and position fraction.
  Clients never name or position these ships. The vessel follows the reverse
  route and advances on the same SOL clock as scheduled traffic, even if the
  pilot disconnects. A bounded population and lifetime prevent unbounded
  accumulation during repeated voyages.

  This is a strategic vessel, not a local combat NPC or tactical instance.
  """
  @spec launch_contact(map(), String.t(), String.t(), pos_integer(), atom(), float()) ::
          {:ok, map()} | {:error, atom()}
  def launch_contact(ships, from_id, to_id, serial, archetype, progress)
      when is_map(ships) and is_binary(from_id) and is_binary(to_id) and
           is_integer(serial) and serial > 0 and is_float(progress) and
           progress >= 0.25 and progress <= 0.75 do
    count = Enum.count(ships, fn {_id, ship} -> Map.get(ship, :procedural?, false) end)

    cond do
      count >= @max_procedural_contacts ->
        {:error, :traffic_capacity}

      not Sol.destination?(from_id) or not Sol.destination?(to_id) or from_id == to_id ->
        {:error, :invalid_route}

      archetype not in [:independent_trader, :patrol, :raider] ->
        {:error, :invalid_archetype}

      true ->
        {name, kind, disposition, faction_id, purpose, cargo} =
          case archetype do
            :independent_trader ->
              {"Harbor", :independent_trader, :neutral, "independent",
               :trade_route, %{"industrial_parts" => 32}}

            :patrol ->
              {"Sentinel", :patrol, :neutral, to_id,
               :sector_patrol, %{"patrol_supplies" => 20}}

            :raider ->
              {"Corsair", :raider, :hostile, "independent",
               :intercept_traffic, %{"salvage" => 18}}
          end

        id = "traffic:sol:cruise-" <> Integer.to_string(serial)

        if Map.has_key?(ships, id) do
          {:error, :duplicate_contact}
        else
          # Start halfway down the opposite lane. Player and vessel converge
          # in midspace; the flyby remains a genuine positional intersection.
          distance_km = Sol.cruise_distance_km(to_id, from_id)
          vessel = %{
            id: id,
            call_sign: name <> "-" <> Integer.to_string(serial),
            kind: kind,
            ship_class: ship_class(kind),
            faction_id: faction_id,
            disposition: disposition,
            purpose: purpose,
            state: :in_transit,
            origin_id: to_id,
            destination_id: from_id,
            home_origin_id: to_id,
            home_destination_id: from_id,
            location_id: to_id,
            cargo: cargo,
            outbound_cargo: cargo,
            return_cargo: cargo,
            cruise_speed_km_s: @cruise_speed_km_s,
            voyage_number: 1,
            elapsed_ms: 0,
            dwell_remaining_ms: 0,
            distance_km: distance_km,
            position_km: position!(to_id),
            procedural?: true,
            lifetime_remaining_ms: @procedural_lifetime_ms
          }

          vessel = Map.put(vessel, :duration_ms, duration(vessel))
          vessel = advance_vessel(vessel, trunc(vessel.duration_ms * progress))
          {:ok, Map.put(ships, id, vessel)}
        end
    end
  end

  def launch_contact(_ships, _from, _to, _serial, _archetype, _progress),
    do: {:error, :invalid_contact}

  @spec advance(map(), non_neg_integer()) :: map()
  def advance(ships, elapsed_ms)
      when is_map(ships) and is_integer(elapsed_ms) and elapsed_ms >= 0 do
    ships
    |> Enum.reduce(%{}, fn {id, vessel}, result ->
      if Map.get(vessel, :procedural?, false) do
        lifetime = vessel.lifetime_remaining_ms - elapsed_ms

        if lifetime <= 0 do
          result
        else
          updated = advance_vessel(vessel, elapsed_ms)
          Map.put(result, id, %{updated | lifetime_remaining_ms: lifetime})
        end
      else
        Map.put(result, id, advance_vessel(vessel, elapsed_ms))
      end
    end)
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
          ship_class: Map.get(vessel, :ship_class, ship_class(vessel.kind)),
          faction_id: vessel.faction_id,
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
          {:ok, hail_response(vessel)}
        else
          {:error, :contact_out_of_range}
        end
    end
  end

  def hail(_ships, _position, _id), do: {:error, :unknown_contact}

  @doc """
  Continue an authenticated encounter's established radio channel after
  the vessel has physically moved out of short-range sensors.

  The caller MUST first verify that this is the exact pending encounter
  for the requesting pilot. Never expose this directly to client sockets:
  ordinary hails still enforce the range check in hail/3.
  """
  @spec hail_established(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  def hail_established(ships, id) when is_map(ships) and is_binary(id) do
    case Map.fetch(ships, id) do
      {:ok, vessel} -> {:ok, hail_response(vessel)}
      :error -> {:error, :unknown_contact}
    end
  end

  def hail_established(_ships, _id), do: {:error, :unknown_contact}

  defp hail_response(vessel) do
    %{
      id: vessel.id,
      call_sign: vessel.call_sign,
      ship_class: Map.get(vessel, :ship_class, ship_class(vessel.kind)),
      faction_id: vessel.faction_id,
      disposition: vessel.disposition,
      origin_id: vessel.origin_id,
      destination_id: vessel.destination_id,
      purpose: vessel.purpose,
      state: vessel.state,
      cargo: vessel.cargo,
      message: vessel.call_sign <> ", " <> vessel.faction_id <> " service. " <>
        "Operating " <> Atom.to_string(vessel.purpose) <>
        " between " <> vessel.origin_id <> " and " <> vessel.destination_id <>
        ". Communications established."
    }
  end

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

  # Ship class is authoritative world data. Merchants and couriers use the
  # new Scow light trader; no client-supplied class or NPC ID is accepted.
  defp ship_class(kind) when kind in
    [:independent_trader, :commercial_freighter, :courier], do: "scow"
  defp ship_class(_other), do: "dart"

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
