defmodule Core.World.Supervisor do
  @moduledoc "Supervises the session registry and map-owned simulation state."

  use Supervisor

  alias Core.World.MapDefinition
  alias Core.World.MapServer
  alias Core.World.NoopEventSink
  alias Core.World.SessionManager
  alias Core.NPC.Catalog, as: NPCCatalog
  alias Core.Universe.Navigation, as: SolarNavigation
  alias Core.Universe.OrbitalEntry

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    registry = Keyword.get(opts, :registry, Core.World.Registry)
    sessions = Keyword.get(opts, :sessions, SessionManager)
    tick_ms = Keyword.get(opts, :tick_ms, 100)
    event_sink = Keyword.get(opts, :event_sink, NoopEventSink)
    auto_tick? = Keyword.get(opts, :auto_tick, true)
    maps = Keyword.get(opts, :maps,
      [MapDefinition.starting_map() | OrbitalEntry.planet_maps()])
    npc_catalog = Keyword.get(opts, :npc_catalog, NPCCatalog.all())
    initial_npcs? = Keyword.get(opts, :initial_npcs?, false)
    auto_respawn? = Keyword.get(opts, :auto_respawn?, false)
    solar_navigation_server =
      Keyword.get(opts, :solar_navigation_server, Module.concat(sessions, SolarNavigation))
    free_flight_maps =
      Keyword.get(opts, :free_flight_maps, Module.concat(sessions, FreeFlightMaps))

    map_children =
      Enum.map(maps, fn definition ->
        definition = MapDefinition.new(definition)
        Supervisor.child_spec(
          {MapServer,
           definition: definition,
           registry: registry,
           tick_ms: tick_ms,
           event_sink: event_sink,
           npc_catalog: npc_catalog,
           initial_npcs?: initial_npcs?,
           auto_respawn?: auto_respawn?,
           solar_navigation_server: solar_navigation_server,
           auto_tick: auto_tick?},
          id: {:world_map, definition.id}
        )
      end)

    children =
      [
        {Registry, keys: :unique, name: registry},
        {SessionManager, name: sessions},
        {SolarNavigation, name: solar_navigation_server, event_sink: event_sink,
         auto_tick: auto_tick?, tick_ms: 1_000,
         voyage_loader: Keyword.get(opts, :voyage_loader),
         voyage_saver: Keyword.get(opts, :voyage_saver),
         # Shared traffic departs on the SOL clock even without connected pilots.
         # Course clicks (including named planets) never mint special ships.
         scheduled_trader_interval_ms: Keyword.get(opts,
           :scheduled_trader_interval_ms, 45_000),
         # Older converging contacts remain opt-in for isolated regression tests.
         procedural_contact_chance: Keyword.get(opts, :procedural_contact_chance, 0.0)},
        {DynamicSupervisor, strategy: :one_for_one, name: free_flight_maps}
      ] ++ map_children

    # Sessions and map entities form one ephemeral consistency boundary. If a
    # process fails, restart the whole world so no stale session can point at a
    # map that has lost its entity state.
    Supervisor.init(children, strategy: :one_for_all)
  end
end
