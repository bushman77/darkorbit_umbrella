defmodule Core.Universe.SpaceBases do
  @moduledoc """
  Server-authoritative SOL orbital bases and planetary forward refineries.

  One facility exists per registered destination (Mercury through Pluto).
  Stock, production, berth occupancy and cargo loading live in the shared
  Navigation GenServer; no per-player or per-trader station process exists.

  Strategic cargo quantities are *manifest units*, not player tonnes.
  Every physical docking transfer debits a real source and credits a real
  destination. Only bounded planetary production introduces new resources.
  Unregistered stations and arbitrary client-controlled cargo are rejected.
  """

  alias Core.Universe.Sol

  @berths 3
  @production_interval_ms 60_000
  @stock_ceiling 10_000

  # V1 provisional industries. Stations seed their operating reserves; after
  # boot, only explicit production and trader unloading can replenish stock.
  # Keep the original game's starter manifests available on their return legs.
  @profiles %{
    "mercury" => {%{"rare_ores" => 220, "refined_minerals" => 300},
                  %{"rare_ores" => 12, "refined_minerals" => 8}},
    "venus" => {%{"civilian_mail" => 380, "refined_minerals" => 280,
                   "industrial_parts" => 120},
                 %{"refined_minerals" => 8, "industrial_parts" => 4}},
    "earth" => {%{"industrial_machinery" => 580, "industrial_parts" => 900,
                   "medical_supplies" => 380, "survey_equipment" => 160,
                   "spare_parts" => 320, "civilian_mail" => 500},
                 %{"industrial_parts" => 16, "industrial_machinery" => 6,
                   "medical_supplies" => 6}},
    "mars" => {%{"refined_minerals" => 480, "rock_samples" => 240,
                  "spare_parts" => 180, "industrial_parts" => 150},
                %{"refined_minerals" => 16, "rock_samples" => 8}},
    "jupiter" => {%{"hydrogen_cells" => 490, "rare_ores" => 220,
                     "research_data" => 140},
                   %{"hydrogen_cells" => 18}},
    "saturn" => {%{"research_data" => 300, "hydrogen_cells" => 340,
                    "rare_ores" => 100},
                  %{"research_data" => 10, "hydrogen_cells" => 9}},
    "uranus" => {%{"hydrogen_cells" => 300, "rare_ores" => 280},
                  %{"hydrogen_cells" => 12, "rare_ores" => 5}},
    "neptune" => {%{"research_data" => 240, "rare_ores" => 240},
                   %{"research_data" => 10, "rare_ores" => 6}},
    "pluto" => {%{"rock_samples" => 360, "rare_ores" => 260},
                 %{"rock_samples" => 14, "rare_ores" => 6}}
  }

  @doc """
  Server-planned export manifest for a new scheduled route. Each refinery
  exports its highest-output commodity, never a client-selected resource.
  This is a *request*, subsequently debited by dispatch/2.
  """
  @spec export_manifest(String.t()) :: %{String.t() => pos_integer()}
  def export_manifest(body_id) do
    {_stock, production} = Map.get(@profiles, body_id,
      {%{"refined_minerals" => 100}, %{"refined_minerals" => 4}})
    {good, _rate} = Enum.max_by(production, fn {id, rate} -> {rate, id} end)
    %{good => 32}
  end

  @doc "Generate one independent orbital hub and forward refinery per destination."
  @spec seed() :: %{String.t() => map()}
  def seed do
    Map.new(Sol.planets(), fn body ->
      # New registered planets get a conservative default refinery without
      # requiring a manual profile before their orbital region can start.
      {stock, production} = Map.get(@profiles, body.id,
        {%{"refined_minerals" => 100}, %{"refined_minerals" => 4}})
      {body.id,
       %{
         id: "sol:base:" <> body.id,
         body_id: body.id,
         name: body.name <> " Orbital Base",
         refinery_id: "sol:refinery:" <> body.id,
         refinery_name: body.name <> " Forward Refinery",
         stock: stock,
         production: production,
         production_elapsed_ms: 0,
         berths: %{},
         berth_count: @berths,
         docking_events: 0
       }}
    end)
  end

  @doc "Only actual registered planetary production can create new goods."
  @spec produce(map(), non_neg_integer()) :: map()
  def produce(bases, elapsed_ms)
      when is_map(bases) and is_integer(elapsed_ms) and elapsed_ms >= 0 do
    Map.new(bases, fn {id, base} ->
      total = base.production_elapsed_ms + elapsed_ms
      cycles = div(total, @production_interval_ms)
      stock =
        if cycles == 0 do
          base.stock
        else
          Enum.reduce(base.production, base.stock, fn {good, rate}, held ->
            Map.update(held, good, min(@stock_ceiling, cycles * rate), fn held_units ->
              # The production ceiling throttles output; it must never
              # discard stock that arrived legitimately on another freighter.
              if held_units >= @stock_ceiling,
                do: held_units,
                else: min(@stock_ceiling, held_units + cycles * rate)
            end)
          end)
        end

      {id, %{base | stock: stock,
        production_elapsed_ms: rem(total, @production_interval_ms)}}
    end)
  end

  @doc """
  Load a new scheduled trader from its actual origin base. The generated
  fixture describes desired cargo; insufficient station stock means a
  partially loaded (or empty) departure. Other kinds do not consume civilian
  refinery stock.
  """
  @spec dispatch(map(), map()) :: {map(), map()}
  def dispatch(bases, %{kind: kind, origin_id: origin, cargo: wanted} = ship)
      when kind in [:commercial_freighter, :courier, :independent_trader] do
    case Map.fetch(bases, origin) do
      {:ok, base} ->
        {loaded, stock} = withdraw(base.stock, wanted)
        {Map.put(bases, origin, %{base | stock: stock}), %{ship | cargo: loaded}}

      :error ->
        {bases, %{ship | cargo: %{}}}
    end
  end

  def dispatch(bases, ship), do: {bases, ship}

  @doc """
  Arrival transfers the inbound manifest to a refinery, then fills the
  opposite route's declared wishlist from real available station stock.
  The transfer occurs exactly once because the ship becomes :docked.
  Full bays leave the trader in :awaiting_berth, carrying its cargo.
  """
  @spec dock(map(), map()) :: {map(), map()}
  def dock(bases, %{destination_id: destination, id: ship_id} = ship) do
    case Map.fetch(bases, destination) do
      {:ok, base} ->
        # The same strategic ship cannot unload twice by retrying a docking
        # event. The normal Navigation state machine only calls this during
        # arrival or while awaiting a bay, but the guard protects helpers too.
        if Enum.any?(base.berths, fn {_bay, held_id} -> held_id == ship_id end) do
          {bases, ship}
        else
          case available_berth(base) do
          nil ->
            {bases, %{ship | state: :awaiting_berth,
              location_id: destination, position_km: position!(destination)}}

          bay ->
            stock = deposit(base.stock, ship.cargo)
            next_destination =
              if destination == ship.home_destination_id,
                do: ship.home_origin_id, else: ship.home_destination_id
            wishlist =
              if next_destination == ship.home_origin_id,
                do: ship.return_cargo, else: ship.outbound_cargo

            {outbound, remaining} = withdraw(stock, wishlist)
            occupied = %{base | stock: remaining,
              berths: Map.put(base.berths, bay, ship_id),
              docking_events: base.docking_events + 1}

            {Map.put(bases, destination, occupied),
             %{ship | state: :docked, location_id: destination,
               position_km: position!(destination),
               cargo: outbound, dwell_remaining_ms: 45_000}}
          end
        end

      :error ->
        {bases, ship}
    end
  end

  @doc "Free the vessel's occupied berth on departure or traffic expiry."
  @spec undock(map(), map()) :: map()
  def undock(bases, %{id: id, location_id: at}) do
    case Map.fetch(bases, at) do
      {:ok, base} ->
        slots = Map.reject(base.berths, fn {_bay, vessel} -> vessel == id end)
        Map.put(bases, at, %{base | berths: slots})

      :error ->
        bases
    end
  end

  @doc "A static read-only map, without station stock or other private data."
  @spec catalog() :: [map()]
  def catalog do
    Sol.planets()
    |> Enum.map(fn body ->
      %{id: "sol:base:" <> body.id, body_id: body.id,
        name: body.name <> " Orbital Base",
        refinery_name: body.name <> " Forward Refinery",
        berth_count: @berths}
    end)
  end

  @doc "Local public docking status; cargo stock stays server-side until trade UI."
  @spec public(map(), String.t()) :: map() | nil
  def public(bases, body_id) do
    case Map.fetch(bases, body_id) do
      {:ok, base} ->
        %{
          id: base.id, body_id: body_id, name: base.name,
          refinery_id: base.refinery_id, refinery_name: base.refinery_name,
          berth_count: base.berth_count,
          occupied_berths: map_size(base.berths),
          berths: Enum.map(1..base.berth_count, fn n ->
            id = "bay-" <> Integer.to_string(n)
            %{id: id, vessel_id: Map.get(base.berths, id)}
          end),
          refinery_status: :operational,
          docking_events: base.docking_events
        }

      :error ->
        nil
    end
  end

  defp available_berth(base) do
    Enum.find_value(1..base.berth_count, fn n ->
      id = "bay-" <> Integer.to_string(n)
      if Map.has_key?(base.berths, id), do: nil, else: id
    end)
  end

  defp withdraw(stock, demand) do
    demand
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.reduce({%{}, stock}, fn {id, wanted}, {manifest, held} ->
      available = max(0, Map.get(held, id, 0))
      amount = if is_integer(wanted) and wanted > 0, do: min(wanted, available), else: 0

      if amount > 0 do
        {Map.put(manifest, id, amount), Map.put(held, id, available - amount)}
      else
        {manifest, held}
      end
    end)
  end

  defp deposit(stock, manifest) do
    Enum.reduce(manifest, stock, fn {id, amount}, held ->
      if is_integer(amount) and amount > 0 do
        Map.update(held, id, amount, &(&1 + amount))
      else
        held
      end
    end)
  end

  defp position!(id) do
    {:ok, point} = Sol.game_position_km(id)
    point
  end
end
