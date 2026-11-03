import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :darkorbit, Darkorbit.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "darkorbit_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :darkorbit_web, DarkorbitWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "c0nFoONi8+4CrFSoOstD+LtVjisAflWssY6zTzAItMovMvO8ncK6gvkR3XQdrqbf",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails
config :darkorbit, Darkorbit.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Keep account tests fast while exercising the same bcrypt code path.
config :bcrypt_elixir, log_rounds: 4

# Tests drive deterministic ticks synchronously; no wall-clock sleeps are
# needed and automatic timers cannot race assertions.
config :core, Core.World, auto_tick: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Preserve historic world:1-1 channel/combat fixtures only during tests.
# The running game starts on the real collision-ready sol:earth region.
config :darkorbit, :legacy_test_earth_sector, true
