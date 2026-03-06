import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/threadr start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :threadr, ThreadrWeb.Endpoint, server: true
end

nats_host = System.get_env("THREADR_NATS_HOST") || "localhost"
nats_port = String.to_integer(System.get_env("THREADR_NATS_PORT") || "4222")
pipeline_enabled = System.get_env("THREADR_BROADWAY_ENABLED") in ~w(true 1 TRUE)

normalize_platform = fn
  nil ->
    nil

  value when is_binary(value) ->
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      platform -> platform
    end
end

parse_channels = fn
  nil ->
    []

  value when is_binary(value) ->
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        []

      String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, channels} when is_list(channels) -> Enum.map(channels, &to_string/1)
          _ -> []
        end

      true ->
        trimmed
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
end

parse_bool = fn
  value when value in [true, "true", "TRUE", "1"] -> true
  _value -> false
end

config :threadr, Threadr.Messaging.Topology,
  pipeline_enabled: pipeline_enabled,
  connections: [
    %{
      host: nats_host,
      port: nats_port
    }
  ]

ingest_platform = normalize_platform.(System.get_env("THREADR_PLATFORM"))
ingest_channels = parse_channels.(System.get_env("THREADR_CHANNELS"))

ingest_enabled =
  System.get_env("THREADR_INGEST_ENABLED") in ~w(true 1 TRUE) or
    ingest_platform in ["irc", "discord"]

config :threadr, Threadr.Ingest,
  enabled: ingest_enabled,
  platform: ingest_platform,
  tenant_subject_name: System.get_env("THREADR_TENANT_SUBJECT"),
  tenant_id: System.get_env("THREADR_TENANT_ID"),
  bot_id: System.get_env("THREADR_BOT_ID"),
  channels: ingest_channels,
  irc: %{
    host: System.get_env("THREADR_IRC_HOST"),
    port: String.to_integer(System.get_env("THREADR_IRC_PORT") || "6667"),
    ssl: parse_bool.(System.get_env("THREADR_IRC_SSL")),
    nick: System.get_env("THREADR_IRC_NICK"),
    user: System.get_env("THREADR_IRC_USER"),
    realname: System.get_env("THREADR_IRC_REALNAME") || "Threadr Bot",
    password: System.get_env("THREADR_IRC_PASSWORD")
  },
  discord: %{
    token: System.get_env("THREADR_DISCORD_TOKEN")
  }

config :threadr,
       :control_plane_token,
       System.get_env("THREADR_CONTROL_PLANE_TOKEN") ||
         Application.get_env(:threadr, :control_plane_token)

config :threadr,
       :token_signing_secret,
       System.get_env("THREADR_TOKEN_SIGNING_SECRET") ||
         Application.get_env(:threadr, :token_signing_secret)

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :threadr, Threadr.Repo,
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

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :threadr, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :threadr, ThreadrWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :threadr, ThreadrWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :threadr, ThreadrWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :threadr, Threadr.Mailer,
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
end
