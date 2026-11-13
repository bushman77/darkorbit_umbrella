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
    do: {127, 0, 0, 1}, else: {0, 0, 0, 0}), port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kqIfy3kcJcfaUSA/cHfmnWh/ByQViFIZM0odCFjLAj1O+aVK6y2MXqB56Gnqng2I",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:darkorbit_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:darkorbit_web, ~w(--watch)]}
  ]

# Trusted local HTTPS replaces local HTTP on the SAME port 4000. Generate
# certificates with mkcert (see clients/tauri/README.md) and opt in with
# DARKORBIT_DEV_HTTPS=1. HTTP remains the default in development.
if System.get_env("DARKORBIT_DEV_HTTPS") == "1" do
  cert_dir = Path.expand("../apps/darkorbit_web/priv/cert", __DIR__)

  config :darkorbit_web, DarkorbitWeb.Endpoint,
    http: false,
    url: [host: "localhost", scheme: "https", port: 4000],
    https: [
      ip: {127, 0, 0, 1},
      port: 4000,
      cipher_suite: :strong,
      certfile: Path.join(cert_dir, "localhost.pem"),
      keyfile: Path.join(cert_dir, "localhost-key.pem")
    ]
end

# The Galaxy headset requires a secure context for orientation sensors.
# Always run its separate HTTPS listener on port 4443 in development.
# Tauri keeps the ordinary HTTP listener on port 4000. No launch flags needed.
# Use a certificate trusted by Android with the LAN address in its SAN.
#
# Prefer an explicit host override for unusual networks; otherwise discover the
# laptop's active private Wi-Fi/LAN IP, prioritizing Wi-Fi over wired/VPN.
# This is intentionally restricted to the dev config: production TLS is
# terminated independently by Caddy.
lan_host =
  case System.get_env("DARKORBIT_DEV_LAN_HOST") do
    host when is_binary(host) and host != "" ->
      String.trim(host)

    _ ->
      interfaces =
        case :inet.getifaddrs() do
          {:ok, found} -> found
          {:error, reason} -> raise "Could not discover headset LAN IP: #{inspect(reason)}"
        end

      candidates =
        for {interface, attrs} <- interfaces,
            :up in Keyword.get(attrs, :flags, []),
            {:addr, {a, b, c, d}} <- attrs,
            a == 10 or (a == 172 and b in 16..31) or
              (a == 192 and b == 168) or (a == 100 and b in 64..127) do
          name = to_string(interface)
          priority =
            cond do
              String.match?(name, ~r/^(wl|wlan|wifi)/i) -> 0
              String.match?(name, ~r/^(en|eth)/i) -> 1
              String.match?(name, ~r/^(usb|rndis)/i) -> 2
              String.match?(name, ~r/^(tailscale|wg|tun|tap)/i) -> 3
              String.match?(name, ~r/^(docker|veth|br-|virbr|podman)/i) -> 9
              true -> 4
            end

          {priority, {a, b, c, d}}
        end

      case candidates |> Enum.sort_by(&elem(&1, 0)) |> List.first() do
        {_, address} -> address |> :inet.ntoa() |> to_string()
        nil ->
          raise "No active private LAN IPv4 for the headset. " <>
                  "Connect Wi-Fi or set DARKORBIT_DEV_LAN_HOST to the laptop's LAN IP."
      end
  end

case :inet.parse_address(String.to_charlist(lan_host)) do
  {:ok, {a, b, c, d}}
      when b in 0..255 and c in 0..255 and d in 1..254 and
             (a == 10 or (a == 172 and b in 16..31) or
                (a == 192 and b == 168) or (a == 100 and b in 64..127)) ->
    :ok

  _ ->
    raise "Headset HTTPS needs a private LAN IPv4 address; got #{inspect(lan_host)}"
end

cert_dir = Path.expand("../apps/darkorbit_web/priv/cert", __DIR__)
certfile = Path.join(cert_dir, "localhost.pem")
keyfile = Path.join(cert_dir, "localhost-key.pem")

unless File.regular?(certfile) and File.regular?(keyfile) do
  raise """
  Headset HTTPS is mandatory in local development, but the TLS certificate
  or key is missing from #{cert_dir}.
  Generate a locally trusted certificate with mkcert containing localhost,
  127.0.0.1 and #{lan_host}; trust the issuing CA on the phone.
  Never commit certificate private keys.
  """
end

config :darkorbit_web, DarkorbitWeb.Endpoint,
  https: [
    ip: {0, 0, 0, 0},
    port: 4443,
    cipher_suite: :strong,
    certfile: certfile,
    keyfile: keyfile
  ]

config :darkorbit_web, :helmet_dev_lan_https_origin,
  "https://" <> lan_host <> ":4443"

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

# The Tauri development webview uses its own local origin while Phoenix
# listens on 4000. Keep this allowlist development-only and exact-match.
# Production does not load config/dev.exs.
config :darkorbit_web, native_dev_socket_origins: ["http://127.0.0.1:1430"]

# HMD pairing uses the laptop's discovered LAN address (e.g. 192.168.x.x)
# but /socket has its own origin check. In development only, accept HTTP
# WebSocket origins matching this machine's active HMD LAN host list.
# Production does not load this setting.
config :darkorbit_web, allow_hmd_lan_socket_origin: true

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
