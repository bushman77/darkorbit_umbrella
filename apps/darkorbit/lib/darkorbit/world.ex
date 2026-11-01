defmodule Darkorbit.World do
  @moduledoc """
  Persistence-aware entry point to the authoritative world simulation.

  Connecting snapshots the active ship's derived speed into the runtime entity.
  Subsequent movement remains independent of PostgreSQL and Phoenix.
  """

  alias Core.World, as: Simulation
  alias Core.World.MapDefinition
  alias Darkorbit.ShipStats
  alias Darkorbit.World.PubSub

  @spec connect(pos_integer(), 1 | 2) :: {:ok, Core.World.Session.t()} | {:error, term()}
  def connect(user_id, config_no \\ 1) do
    with {:ok, stats} <- ShipStats.for_active_ship(user_id, config_no) do
      Simulation.connect(user_id, stats)
    end
  end

  defdelegate disconnect(session_id), to: Simulation
  defdelegate move(session_id, destination), to: Simulation

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(map_id \\ MapDefinition.starting_map_id()), do: Simulation.snapshot(map_id)

  @spec tick(String.t()) :: {:ok, map()} | {:error, term()}
  def tick(map_id \\ MapDefinition.starting_map_id()), do: Simulation.tick(map_id)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(map_id \\ MapDefinition.starting_map_id()) do
    Phoenix.PubSub.subscribe(Darkorbit.PubSub, PubSub.topic(map_id))
  end
end
