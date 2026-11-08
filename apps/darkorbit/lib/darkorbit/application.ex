defmodule Darkorbit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    world_options = Application.get_env(:core, Core.World, [])

    # The Core physics simulator stays independent of PostgreSQL; the
    # actual game supervisor supplies server-only persistence callbacks.
    world_options =
      if Application.get_env(:darkorbit, :persist_pilot_locations, true) do
        Keyword.merge(world_options,
          voyage_loader: &Darkorbit.PilotLocation.load_navigation/1,
          voyage_saver: &Darkorbit.PilotLocation.save_navigation/2)
      else
        world_options
      end

    children = [
      Darkorbit.Repo,
      {DNSCluster, query: Application.get_env(:darkorbit, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Darkorbit.PubSub},
      {Core.World.Supervisor, world_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Darkorbit.Supervisor)
  end
end
