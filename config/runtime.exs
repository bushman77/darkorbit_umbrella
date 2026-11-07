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

  # Email provider is independent from the registration switch. Configure and
  # smoke-test a real transport before opening public registrations.
  email_provider =
    System.get_env("SPACE_NOVA_EMAIL_PROVIDER") ||
      if(System.get_env("RESEND_API_KEY"), do: "resend", else: "none")

  registration_from = System.get_env("REGISTRATION_FROM_EMAIL")
  sender_valid? =
    is_binary(registration_from) and
      Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, registration_from)

  present? = fn key ->
    case System.get_env(key) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  smtp_host = System.get_env("SMTP_HOST")
  smtp_port =
    case Integer.parse(System.get_env("SMTP_PORT") || "587") do
      {port, ""} when port in [465, 587, 2525] -> port
      _ -> nil
    end

  transport_ready? =
    case email_provider do
      "resend" ->
        sender_valid? and present?.("RESEND_API_KEY")

      "smtp" ->
        sender_valid? and present?.("SMTP_HOST") and present?.("SMTP_USERNAME") and
          present?.("SMTP_PASSWORD") and not is_nil(smtp_port) and
          not String.contains?(smtp_host || "", ["/", " ", "@", ":"])

      _ ->
        false
    end

  registration_open? =
    System.get_env("SPACE_NOVA_REGISTRATION_OPEN") in ~w(1 true)

  config :darkorbit_web,
    registration_email_enabled: transport_ready? and registration_open?,
    email_delivery_configured: transport_ready?,
    email_provider: if(transport_ready?, do: email_provider, else: "none"),
    registration_from: registration_from || "noreply@localhost"

  cond do
    not transport_ready? ->
      if email_provider != "none" do
        IO.warn("Space Nova email configuration is incomplete; outbound mail and public registration are disabled")
      end

    email_provider == "resend" ->
      config :darkorbit, Darkorbit.Mailer,
        adapter: Swoosh.Adapters.Resend,
        api_key: System.fetch_env!("RESEND_API_KEY")

    email_provider == "smtp" ->
      # Enforce both CA-chain and hostname verification. Plain SMTP and
      # opportunistic STARTTLS are not permitted for production delivery.
      tls_options = [
        # gen_smtp's socket wrapper otherwise supplies depth: 0, which
        # rejects Gmail's intermediate CA certificate chain.
        versions: [:"tlsv1.2", :"tlsv1.3"],
        depth: 10,
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]

      connection_options =
        if smtp_port == 465 do
          [ssl: true, sockopts: tls_options]
        else
          [ssl: false, tls_options: tls_options]
        end

      config :darkorbit, Darkorbit.Mailer,
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: smtp_host,
          port: smtp_port,
          username: System.fetch_env!("SMTP_USERNAME"),
          password: System.fetch_env!("SMTP_PASSWORD"),
          auth: :always,
          tls: :always,
          retries: 1
        ] ++ connection_options
  end

  if registration_open? and not transport_ready? do
    IO.warn("Space Nova registration was requested but mail delivery is not ready; signup remains disabled")
  end

  config :darkorbit, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
