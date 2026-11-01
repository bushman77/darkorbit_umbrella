defmodule Darkorbit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    world_options = Application.get_env(:core, Core.World, [])

    children = [
      Darkorbit.Repo,
      {DNSCluster, query: Application.get_env(:darkorbit, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Darkorbit.PubSub},
      {Core.World.Supervisor, world_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Darkorbit.Supervisor)
  end
end
