import Config

# Configure your database
config :darkorbit, Darkorbit.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "darkorbit_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :darkorbit_web, DarkorbitWeb.Endpoint,
  # Dev cockpit and paired HMD must both reach the same Phoenix server.
  # Bind all interfaces by default for LAN headset access. Run on a trusted
  # network; set DARKORBIT_LOOPBACK_ONLY=1 to restrict access to this laptop.
  http: [ip: if(System.get_env("DARKORBIT_LOOPBACK_ONLY") == "1",
    do: {127, 0, 0, 1}, else: {0, 0, 0, 0})],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kqIfy3kcJcfaUSA/cHfmnWh/ByQViFIZM0odCFjLAj1O+aVK6y2MXqB56Gnqng2I",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:darkorbit_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:darkorbit_web, ~w(--watch)]}
  ]

# The native Linux client can use a trusted local HTTPS endpoint.
# Generate the developer certificate with mkcert (see clients/tauri/README.md)
# and opt in with DARKORBIT_DEV_HTTPS=1. HTTP on port 4000 remains available
# for ordinary browser testing and HMD development.
if System.get_env("DARKORBIT_DEV_HTTPS") == "1" do
  cert_dir = Path.expand("../apps/darkorbit_web/priv/cert", __DIR__)

  config :darkorbit_web, DarkorbitWeb.Endpoint,
    https: [
      ip: {127, 0, 0, 1},
      port: 4001,
      cipher_suite: :strong,
      certfile: Path.join(cert_dir, "localhost.pem"),
      keyfile: Path.join(cert_dir, "localhost-key.pem")
    ]
end

# Reload browser tabs when matching files change.
config :darkorbit_web, DarkorbitWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      # Gettext translations
      ~r"priv/gettext/.*\.po$",
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/darkorbit_web/router\.ex$",
      ~r"lib/darkorbit_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

# Development registration emails remain local (Swoosh.Local).
config :darkorbit_web, registration_email_enabled: true,
  registration_from: "noreply@localhost"

# Enable dev routes for dashboard and mailbox
config :darkorbit_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
