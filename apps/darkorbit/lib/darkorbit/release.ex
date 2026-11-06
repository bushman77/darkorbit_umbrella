defmodule Darkorbit.Release do
  @moduledoc """
  Explicit database migration entry point for an OTP release.

  Run with \`bin/space_mmo eval 'Darkorbit.Release.migrate()'\` after setting
  DATABASE_URL, SECRET_KEY_BASE and the production TLS configuration.
  Deployment remains separate from publishing a GitHub Release.
  """

  @spec migrate() :: :ok
  def migrate do
    Application.load(:darkorbit)

    for repo <- Application.fetch_env!(:darkorbit, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn running_repo ->
          Ecto.Migrator.run(running_repo, :up, all: true)
        end)
    end

    :ok
  end
end
