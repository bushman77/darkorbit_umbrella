defmodule Darkorbit.World do
  @moduledoc """
  Persistence-aware entry point to the authoritative world simulation.

  Connecting snapshots the active ship's derived combat and movement stats
  into the runtime entity. Subsequent simulation remains independent of
  PostgreSQL and Phoenix.
  """

  alias Core.World, as: Simulation
  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.Universe.OrbitalEntry
  alias Core.World.SessionManager
  alias Core.World.MapDefinition
  alias Darkorbit.Accounts
  alias Darkorbit.Accounts.PlayerAccount
  alias Darkorbit.Fleet
  alias Darkorbit.Loadouts
  alias Darkorbit.ShipStats
  alias Darkorbit.World.PubSub

  @doc "Resolve an authenticated pilot's current planetary map and arrival pose."
  @spec region_for_player(pos_integer()) :: {:ok, map()} | {:error, term()}
  def region_for_player(user_id) when is_integer(user_id) and user_id > 0 do
    server = Module.concat(SessionManager, SolarNavigation)

    with {:ok, navigation} <- SolarNavigation.snapshot(server, user_id),
         {:ok, entry} <- OrbitalEntry.entry(
           navigation.arrival_origin_id, navigation.location_id,
           user_id, navigation.voyage_number
         ) do
      {:ok, entry}
    end
  end

  @spec connect(pos_integer(), 1 | 2, keyword()) ::
          {:ok, Core.World.Session.t()} | {:error, term()}
  def connect(user_id, config_no \\ 1, opts \\ []) do
    with {:ok, stats} <- ShipStats.for_active_ship(user_id, config_no),
         {:ok, entry} <- region_for_player(user_id) do
      requested_map = Keyword.get(opts, :map_id, entry.map_id)

      if requested_map == entry.map_id do
        Simulation.connect(user_id, stats, map_id: requested_map, entry: entry)
      else
        {:error, :wrong_orbital_region}
      end
    end
  end

  defdelegate disconnect(session_id), to: Simulation
  defdelegate move(session_id, destination), to: Simulation
  defdelegate plot_course(session_id, waypoints), to: Simulation
  defdelegate stop_navigation(session_id), to: Simulation
  defdelegate solar_snapshot(session_id), to: Simulation
  defdelegate solar_set_course(session_id, destination_id), to: Simulation
  defdelegate solar_cancel_course(session_id), to: Simulation
  defdelegate solar_hail(session_id, contact_id), to: Simulation
  defdelegate flight_controls(session_id, input), to: Simulation
  defdelegate select_target(session_id, target_id), to: Simulation
  defdelegate clear_target(session_id), to: Simulation
  defdelegate engage_combat(session_id), to: Simulation
  defdelegate disengage_combat(session_id), to: Simulation
  defdelegate toggle_laser_fire(session_id), to: Simulation
  defdelegate activate_action(session_id, slot), to: Simulation
  defdelegate attack(session_id), to: Simulation
  defdelegate fire_ready_weapon(session_id), to: Simulation

  @spec action_hotbar() :: [Core.Combat.ActionCatalog.slot()]
  def action_hotbar, do: Core.Combat.ActionCatalog.hotbar()

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(map_id \\ MapDefinition.starting_map_id()), do: Simulation.snapshot(map_id)

  @spec tick(String.t()) :: {:ok, map()} | {:error, term()}
  def tick(map_id \\ MapDefinition.starting_map_id()), do: Simulation.tick(map_id)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(map_id \\ MapDefinition.starting_map_id()) do
    Phoenix.PubSub.subscribe(Darkorbit.PubSub, PubSub.topic(map_id))
  end

  @spec player_status(pos_integer(), 1 | 2) :: {:ok, map()} | {:error, term()}
  def player_status(user_id, config_no \\ 1)
      when is_integer(user_id) and config_no in [1, 2] do
    with %PlayerAccount{} = account <- Accounts.get_player_account!(user_id),
         {:ok, player_ship} <- Fleet.get_active_ship(user_id),
         %{} = loadout <- Loadouts.get_loadout(player_ship.id, config_no),
         {:ok, stats} <- ShipStats.calculate(user_id, player_ship.id, config_no),
         {:ok, ship} <- Core.Ships.Catalog.fetch(player_ship.ship_id) do
      {:ok,
       %{
         pilot: summarize_player(account),
         ship: %{id: ship.id, name: ship.name},
         stats: Map.from_struct(stats),
         configuration: %{
           number: config_no,
           lasers: equipment_slots(loadout.lasers),
           generators: equipment_slots(loadout.generators),
           drones: equipment_slots(loadout.drones)
         }
       }}
    else
      nil -> {:error, :loadout_not_found}
      error -> error
    end
  rescue
    Ecto.NoResultsError -> {:error, :player_not_found}
  end

  @spec player_summaries([pos_integer()]) :: %{optional(pos_integer()) => map()}
  def player_summaries(player_ids) when is_list(player_ids) do
    player_ids
    |> Accounts.get_player_accounts()
    |> Map.new(fn account -> {account.id, summarize_player(account)} end)
  end

  @spec player_summary(pos_integer()) :: map() | nil
  def player_summary(player_id) when is_integer(player_id) do
    case Accounts.get_player_accounts([player_id]) do
      [account] -> summarize_player(account)
      [] -> nil
    end
  end

  defp summarize_player(%PlayerAccount{} = account) do
    %{
      id: account.id,
      pilot_name: account.pilot_name,
      username: account.username,
      faction_id: account.faction_id
    }
  end

  defp equipment_slots(equipment) when is_map(equipment) do
    ["ship", "drones", "slots"]
    |> Enum.flat_map(fn location ->
      equipment
      |> Map.get(location, [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn
        {nil, _slot} -> []
        {item_id, slot} -> [equipment_slot(item_id, location, slot)]
      end)
    end)
  end

  defp equipment_slots(_slots), do: []

  defp equipment_slot(item_id, location, slot) do
    case Core.Equipment.Catalog.fetch(item_id) do
      {:ok, item} ->
        %{
          location: location,
          slot: slot,
          id: item.id,
          name: item.name,
          category: item.category
        }

      :error ->
        %{location: location, slot: slot, id: item_id, name: item_id, category: :unknown}
    end
  end
end
