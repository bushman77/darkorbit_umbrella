defmodule Darkorbit.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp deps do
    [
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  #
  # Aliases listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp aliases do
    [
      # run `mix setup` in all child apps
      setup: ["cmd mix setup"],
      # Phoenix assets aliases live in the web child, not the umbrella root.
      # Route root-level commands explicitly to the web app so cockpit changes
      # cannot silently keep using an older JS bundle.
      "assets.setup": [fn _args -> run_web_asset_task("assets.setup") end],
      "assets.build": [fn _args -> run_web_asset_task("assets.build") end],
      "assets.deploy": [fn _args -> run_web_asset_task("assets.deploy") end],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test"
      ]
    ]
  end
  defp run_web_asset_task(task) do
    project_dir = Path.expand("apps/darkorbit_web", __DIR__)
    Mix.shell().info("Building assets in #{project_dir} via mix #{task}")

    case System.cmd("mix", [task], cd: project_dir, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info(output)
        :ok

      {output, exit_code} ->
        Mix.shell().error(output)
        Mix.raise("Web asset task #{task} failed with exit code #{exit_code}")
    end
  end

end
