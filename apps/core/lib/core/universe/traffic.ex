defmodule Core.Universe.Traffic do
  @moduledoc """
  Deterministic, player-independent SOL traffic for the first living-universe
  slice. This is strategic game-km movement, never a tactical map spawn.

  Every traffic vessel has a cargo manifest, purpose, route and schedule.
  It continues traveling and docking without connected pilots. Sensor contacts
  and hails are derived from server-owned positions; players do not create or
  steer the freighter by encountering it.

  State survives player disconnects and tactical sessions while the
  supervised world runs. Tactical instances borrow the vessel's current
  condition and reconcile it on exit. Database persistence across server
  restarts and genuinely shared tactical arenas are later milestones.
  """

  alias Core.Universe.Sol
  alias Core.Universe.SpaceBases
  alias Core.Factions
  alias Core.NPC.Catalog, as: NPCCatalog

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
      {"meridian-01", "Meridian-01", :commercial_freighter, :neutral, "sol_merchant_league",
       "earth", "mars", 0.0, :scheduled_delivery,
       %{"industrial_machinery" => 120}, %{"refined_minerals" => 85}},
      # Begins > 2M game-km from Earth, but is catchable mid Earth→Venus.
      {"vesper-02", "Vesper-02", :courier, :neutral, "helios_couriers",
       "earth", "venus", 0.22, :express_delivery,
       %{"medical_supplies" => 48}, %{"civilian_mail" => 120}},
      {"wayfinder-04", "Wayfinder-04", :survey_vessel, :neutral, "sol_surveyors",
       "earth", "mars", 0.22, :scientific_survey,
       %{"survey_equipment" => 25}, %{"rock_samples" => 18}},
      {"sentinel-07", "Sentinel-07", :patrol, :neutral, "venus",
       "venus", "mercury", 0.40, :sector_patrol,
       %{"patrol_supplies" => 40}, %{"patrol_supplies" => 40}},
      {"aurora-12", "Aurora-12", :commercial_freighter, :neutral, "outer_rim_traders",
       "mars", "jupiter", 0.43, :scheduled_delivery,
       %{"spare_parts" => 72}, %{"rare_ores" => 26}},
      {"sable-18", "Sable-18", :independent_trader, :neutral, "outer_rim_traders",
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
          combat: initial_condition(kind),
          settled_encounters: MapSet.new(),
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
              {"Corsair", :raider, :hostile, "independent_raiders",
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
            combat: initial_condition(kind),
            settled_encounters: MapSet.new(),
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

  @doc """
  Launch one server-scheduled trader on an actual planet-to-planet lane.
  No pilot action or requested destination chooses this vessel. Its stable
  route and origin are shared by all pilots, including free-waypoint pilots.
  The initial manifest is a server-owned *load request*. Navigation debits
  actual Earth/planet refinery stock using SpaceBases.dispatch/2 before the
  new vessel appears in the shared SOL traffic map.
  """
  @spec launch_scheduled_trader(map(), String.t(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, atom()}
  def launch_scheduled_trader(ships, from_id, to_id, serial)
      when is_map(ships) and is_binary(from_id) and is_binary(to_id) and
           is_integer(serial) and serial > 0 do
    id = "traffic:sol:cruise-" <> Integer.to_string(serial)
    active = Enum.count(ships, fn {_key, ship} ->
      Map.get(ship, :procedural?, false)
    end)

    cond do
      active >= @max_procedural_contacts -> {:error, :traffic_capacity}
      not Sol.destination?(from_id) or not Sol.destination?(to_id) or
          from_id == to_id -> {:error, :invalid_route}
      Map.has_key?(ships, id) -> {:error, :duplicate_contact}
      true ->
        provisional_cargo = SpaceBases.export_manifest(from_id)
        return_request = SpaceBases.export_manifest(to_id)
        dist = Sol.cruise_distance_km(from_id, to_id)
        vessel = %{
          id: id,
          call_sign: "Hauler-" <> Integer.to_string(serial),
          kind: :independent_trader,
          ship_class: "scow",
          faction_id: scheduled_trader_faction(from_id, to_id),
          disposition: :neutral,
          purpose: :trade_route,
          state: :in_transit,
          origin_id: from_id,
          destination_id: to_id,
          home_origin_id: from_id,
          home_destination_id: to_id,
          location_id: from_id,
          cargo: provisional_cargo,
          outbound_cargo: provisional_cargo,
          return_cargo: return_request,
          combat: initial_condition(:independent_trader),
          settled_encounters: MapSet.new(),
          cruise_speed_km_s: @cruise_speed_km_s,
          voyage_number: 1,
          elapsed_ms: 0,
          dwell_remaining_ms: 0,
          distance_km: dist,
          position_km: position!(from_id),
          procedural?: true,
          lifetime_remaining_ms: @procedural_lifetime_ms
        }

        {:ok, Map.put(ships, id, Map.put(vessel, :duration_ms, duration(vessel)))}
    end
  end

  def launch_scheduled_trader(_ships, _from, _to, _serial),
    do: {:error, :invalid_route}

  # A regular shipping line keeps its allegiance for every leg of the
  # route. Selection is world-defined, not derived from the player's course.
  defp scheduled_trader_faction(from, to) do
    outer = ~w(jupiter saturn uranus neptune pluto)
    if from in outer or to in outer,
      do: "outer_rim_traders", else: "sol_merchant_league"
  end

  @doc """
  Advance every ship on the SOL clock. A vessel currently leased to a
  tactical encounter continues toward its destination but cannot finish
  its strategic voyage and reuse its voyage number while combat is active.
  Its procedural lifetime also cannot expire until the lease is released.
  """
  @spec advance(map(), non_neg_integer()) :: map()
  @spec advance(map(), non_neg_integer(), MapSet.t(String.t())) :: map()
  def advance(ships, elapsed_ms, active_contact_ids \\ MapSet.new())

  def advance(ships, elapsed_ms, active_contact_ids)
      when is_map(ships) and is_integer(elapsed_ms) and elapsed_ms >= 0 and
           is_struct(active_contact_ids, MapSet) do
    ships
    |> Enum.reduce(%{}, fn {id, vessel}, result ->
      leased? = MapSet.member?(active_contact_ids, id)
      allowed_ms =
        if leased? and vessel.state == :in_transit do
          max(0, min(elapsed_ms, vessel.duration_ms - vessel.elapsed_ms - 1))
        else
          elapsed_ms
        end

      updated = advance_vessel(vessel, allowed_ms)

      if Map.get(vessel, :procedural?, false) do
        remaining = vessel.lifetime_remaining_ms - elapsed_ms

        if remaining <= 0 and not leased? do
          result
        else
          Map.put(result, id, %{updated | lifetime_remaining_ms: max(1, remaining)})
        end
      else
        Map.put(result, id, updated)
      end
    end)
  end

  @doc """
  Commit the only authoritative combat result against an existing strategic
  vessel and voyage. These fields are produced by the map-owned simulation,
  never by a player payload. A settlement is recorded at most once and can
  only decrease the preexisting hull/shields. Cargo is never awarded here.
  """
  @doc """
  Advance shared traffic together with real refineries and occupied berths.

  Navigation uses this path; the legacy advance/3 remains available for
  isolated movement fixtures. No merchant may magically refill its cargo on
  departure: inbound units are unloaded and outbound units are withdrawn
  from the owning planet's stock exactly once, at docking.
  """
  @spec advance_with_bases(map(), non_neg_integer(), map(), MapSet.t(String.t())) ::
          {map(), map()}
  def advance_with_bases(ships, elapsed_ms, bases, active_contact_ids \\ MapSet.new())

  def advance_with_bases(ships, elapsed_ms, bases, active_contact_ids)
      when is_map(ships) and is_map(bases) and
           is_integer(elapsed_ms) and elapsed_ms >= 0 and
           is_struct(active_contact_ids, MapSet) do
    produced = SpaceBases.produce(bases, elapsed_ms)

    ships
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.reduce({%{}, produced}, fn {id, vessel}, {fleet, station_state} ->
      leased? = MapSet.member?(active_contact_ids, id)
      allowed_ms =
        if leased? and vessel.state == :in_transit do
          max(0, min(elapsed_ms, vessel.duration_ms - vessel.elapsed_ms - 1))
        else
          elapsed_ms
        end

      {updated, station_state} =
        if vessel.kind in [:commercial_freighter, :courier, :independent_trader] and
             vessel.disposition != :hostile do
          advance_vessel_with_bases(vessel, allowed_ms, station_state)
        else
          {advance_vessel(vessel, allowed_ms), station_state}
        end

      if Map.get(vessel, :procedural?, false) do
        remaining = vessel.lifetime_remaining_ms - elapsed_ms

        if remaining <= 0 and not leased? do
          {fleet, SpaceBases.undock(station_state, updated)}
        else
          {Map.put(fleet, id, %{updated | lifetime_remaining_ms: max(1, remaining)}),
           station_state}
        end
      else
        {Map.put(fleet, id, updated), station_state}
      end
    end)
  end

  defp advance_vessel_with_bases(%{state: state} = vessel, _elapsed, bases)
       when state in [:destroyed, :disabled], do: {vessel, bases}

  defp advance_vessel_with_bases(%{state: :in_transit} = vessel, elapsed, bases) do
    remaining = max(0, vessel.duration_ms - vessel.elapsed_ms)
    used = min(remaining, elapsed)
    next = vessel.elapsed_ms + used

    if next >= vessel.duration_ms do
      landed = %{vessel | elapsed_ms: vessel.duration_ms,
        position_km: position!(vessel.destination_id),
        location_id: vessel.destination_id}
      {bases, docked} = SpaceBases.dock(bases, landed)
      advance_vessel_with_bases(docked, elapsed - used, bases)
    else
      progress = next / vessel.duration_ms
      moved = %{vessel | elapsed_ms: next,
        position_km: Sol.interpolate_game_position(
          position!(vessel.origin_id), position!(vessel.destination_id), progress)}
      {moved, bases}
    end
  end

  defp advance_vessel_with_bases(%{state: :awaiting_berth} = vessel, elapsed, bases) do
    {bases, docked} = SpaceBases.dock(bases, vessel)

    if docked.state == :docked do
      advance_vessel_with_bases(docked, elapsed, bases)
    else
      {docked, bases}
    end
  end

  defp advance_vessel_with_bases(%{state: :docked} = vessel, elapsed, bases) do
    used = min(elapsed, vessel.dwell_remaining_ms)
    remaining = vessel.dwell_remaining_ms - used

    if remaining == 0 do
      origin = vessel.location_id
      destination =
        if origin == vessel.home_destination_id,
          do: vessel.home_origin_id, else: vessel.home_destination_id
      next = %{vessel |
        state: :in_transit, origin_id: origin, destination_id: destination,
        elapsed_ms: 0, dwell_remaining_ms: 0,
        voyage_number: vessel.voyage_number + 1,
        distance_km: Sol.cruise_distance_km(origin, destination),
        position_km: position!(origin)}
      next = Map.put(next, :duration_ms, duration(next))
      advance_vessel_with_bases(next, elapsed - used, SpaceBases.undock(bases, vessel))
    else
      {%{vessel | dwell_remaining_ms: remaining}, bases}
    end
  end

  @spec settle(map(), map(), map(), atom()) :: {:ok, map()} | {:error, atom()}
  def settle(ships, identity, report, outcome),
    do: settle(ships, identity, report, outcome, %{})

  @doc "Optional debit contains verified strategic units seized under DB receipt."
  @spec settle(map(), map(), map(), atom(), map()) :: {:ok, map()} | {:error, atom()}
  def settle(ships, %{contact_id: id, voyage_number: voyage, encounter_id: encounter_id},
             report, outcome, cargo_debit)
      when is_map(ships) and is_binary(id) and is_integer(voyage) and
           is_binary(encounter_id) and is_map(report) and is_map(cargo_debit) do
    case Map.fetch(ships, id) do
      :error -> {:error, :unknown_contact}
      {:ok, vessel} ->
        old = vessel.combat
        settled = Map.get(vessel, :settled_encounters, MapSet.new())

        cond do
          MapSet.member?(settled, encounter_id) ->
            {:error, :already_settled}

          vessel.voyage_number != voyage ->
            {:error, :stale_voyage}

          old.status != :alive ->
            {:error, :vessel_unavailable}

          not valid_report?(old, report, outcome) ->
            {:error, :invalid_combat_report}

          not valid_cargo_debit?(vessel.cargo, cargo_debit, outcome) ->
            {:error, :invalid_cargo_debit}

          true ->
            updated_combat = Map.take(report, [:hull, :max_hull, :shields, :max_shields, :status])
            state =
              case outcome do
                :victory -> :destroyed
                :surrender -> :disabled
                _ -> if(report.status == :surrendered, do: :disabled,
                       else: vessel.state)
              end

            updated =
              vessel
              |> Map.put(:combat, updated_combat)
              |> Map.put(:state, state)
              |> Map.put(:cargo, debit_cargo(vessel.cargo, cargo_debit))
              |> Map.put(:settled_encounters, MapSet.put(settled, encounter_id))

            {:ok, Map.put(ships, id, updated)}
        end
    end
  end

  def settle(_ships, _identity, _report, _outcome, _debit),
    do: {:error, :invalid_combat_report}

  defp valid_cargo_debit?(manifest, debit, outcome) when is_map(manifest) do
    (outcome == :surrender or map_size(debit) == 0) and
      Enum.all?(debit, fn {id, units} ->
        is_binary(id) and is_integer(units) and units > 0 and
          Map.get(manifest, id, 0) >= units
      end)
  end

  defp valid_cargo_debit?(_, _, _), do: false

  defp debit_cargo(manifest, debit) do
    Enum.reduce(debit, manifest, fn {id, units}, remaining ->
      case Map.fetch!(remaining, id) - units do
        0 -> Map.delete(remaining, id)
        left -> Map.put(remaining, id, left)
      end
    end)
  end

  defp valid_report?(old, report, outcome) do
    expected_status =
      case outcome do
        :victory -> :destroyed
        :surrender -> :surrendered
        value when value in [:retreat, :defeat, :escaped] -> :alive
        _ -> :invalid
      end

    # A pilot may retreat (or be defeated) after the merchant has already
    # surrendered; the surrender remains real, but cargo is not awarded.
    reported_status = Map.get(report, :status)
    compatible_status? =
      reported_status == expected_status or
        (outcome in [:retreat, :defeat] and reported_status == :surrendered)

    expected_status != :invalid and compatible_status? and
      Map.get(report, :max_hull) == old.max_hull and
      Map.get(report, :max_shields) == old.max_shields and
      is_integer(Map.get(report, :hull)) and
      is_integer(Map.get(report, :shields)) and
      report.hull >= 0 and report.hull <= old.hull and
      report.shields >= 0 and report.shields <= old.shields and
      # Zero hull is valid only for a destroyed vessel; this also rejects
      # alive/surrendered reports with zero hull.
      (reported_status == :destroyed) == (report.hull == 0)
  end

  defp initial_condition(kind) do
    definition = NPCCatalog.fetch!(ship_class(kind))
    %{
      hull: definition.max_hull, max_hull: definition.max_hull,
      shields: definition.max_shields, max_shields: definition.max_shields,
      status: :alive
    }
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

      if distance <= @sensor_radius_km and vessel.combat.status != :destroyed do
        [%{
          id: vessel.id,
          call_sign: vessel.call_sign,
          kind: vessel.kind,
          ship_class: Map.get(vessel, :ship_class, ship_class(vessel.kind)),
          faction_id: vessel.faction_id,
          faction_name: Factions.name(vessel.faction_id) || "Unregistered Organization",
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
      {:ok, %{combat: %{status: :destroyed}}} ->
        {:error, :unknown_contact}
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
      {:ok, %{combat: %{status: :destroyed}}} -> {:error, :unknown_contact}
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
      faction_name: Factions.name(vessel.faction_id) || "Unregistered Organization",
      disposition: vessel.disposition,
      origin_id: vessel.origin_id,
      destination_id: vessel.destination_id,
      purpose: vessel.purpose,
      state: vessel.state,
      cargo: vessel.cargo,
      message: vessel.call_sign <> ", " <>
          (Factions.name(vessel.faction_id) || "unregistered organization") <> " service. " <>
        "Operating " <> Atom.to_string(vessel.purpose) <>
        " between " <> vessel.origin_id <> " and " <> vessel.destination_id <>
        ". Communications established."
    }
  end

  @spec sensor_radius_km() :: float()
  def sensor_radius_km, do: @sensor_radius_km

  defp advance_vessel(vessel, 0), do: vessel

  # Destroyed and disabled ships keep their identity/manifest but cannot
  # complete deliveries, produce return cargo, or spawn a new voyage.
  defp advance_vessel(%{state: state} = vessel, _delta_ms)
       when state in [:destroyed, :disabled], do: vessel

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
