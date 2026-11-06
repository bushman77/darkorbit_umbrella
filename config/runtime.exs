import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Local Phoenix listens on TCP 4000. Production supports HTTPS via Caddy
# on 443, or optional direct Phoenix TLS on 4000.

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :darkorbit, Darkorbit.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Explicitly opt into Caddy TLS termination on EC2. In proxy mode,
  # Phoenix listens on loopback only and generates public HTTPS:443 URLs.
  # Other deployments can continue terminating TLS directly on port 4000.
  behind_proxy? = System.get_env("SPACE_NOVA_PROXY_MODE") in ~w(1 true)

  config :darkorbit_web, DarkorbitWeb.Endpoint,
    url: [
      host: System.get_env("PHX_HOST", "spacenova.ddns.net"),
      scheme: "https",
      port: if(behind_proxy?, do: 443, else: 4000)
    ],
    server: true,
    secret_key_base: secret_key_base

  if behind_proxy? do
    # Never expose this plaintext listener outside the EC2 loopback interface.
    config :darkorbit_web, DarkorbitWeb.Endpoint,
      http: [ip: {127, 0, 0, 1}, port: 4000],
      https: false
  else
    tls_certfile =
      System.get_env("SPACE_NOVA_TLS_CERTFILE") ||
        raise "SPACE_NOVA_TLS_CERTFILE must point to the production TLS certificate PEM"

    tls_keyfile =
      System.get_env("SPACE_NOVA_TLS_KEYFILE") ||
        raise "SPACE_NOVA_TLS_KEYFILE must point to the production TLS private key PEM"

    config :darkorbit_web, DarkorbitWeb.Endpoint,
      http: false,
      https: [
        ip: {0, 0, 0, 0},
        port: 4000,
        cipher_suite: :strong,
        certfile: tls_certfile,
        keyfile: tls_keyfile
      ]
  end

  # In proxy mode Caddy handles trusted TLS certificates/renewal.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :darkorbit, Darkorbit.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Public pilot registration requires a real outbound email provider.
  # An unverified account may not log in. Never use Swoosh.Local in production
  # for public registrations: its messages would never reach users.
  registration_api_key = System.get_env("RESEND_API_KEY")
  registration_from = System.get_env("REGISTRATION_FROM_EMAIL")
  registration_enabled? =
    is_binary(registration_api_key) and byte_size(registration_api_key) > 0 and
      is_binary(registration_from) and byte_size(registration_from) > 0

  config :darkorbit_web,
    registration_email_enabled: registration_enabled?,
    registration_from: registration_from || "noreply@localhost"

  if registration_enabled? do
    config :darkorbit, Darkorbit.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: registration_api_key
  end

  config :darkorbit, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
