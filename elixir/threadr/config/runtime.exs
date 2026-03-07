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

parse_integer = fn
  nil ->
    nil

  value when is_integer(value) ->
    value

  value when is_binary(value) ->
    value
    |> String.trim()
    |> case do
      "" -> nil
      integer -> String.to_integer(integer)
    end
end

parse_float = fn
  nil ->
    nil

  value when is_float(value) ->
    value

  value when is_integer(value) ->
    value / 1

  value when is_binary(value) ->
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      float ->
        {parsed, _rest} = Float.parse(float)
        parsed
    end
end

normalize_module = fn
  nil ->
    nil

  value when is_binary(value) ->
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      module_name ->
        Module.concat([module_name])
    end
end

env_or_legacy = fn primary, legacy ->
  System.get_env(primary) || System.get_env(legacy)
end

config :threadr, Threadr.Messaging.Topology,
  messaging_enabled:
    case System.get_env("THREADR_MESSAGING_ENABLED") do
      nil ->
        Keyword.get(Application.get_env(:threadr, Threadr.Messaging.Topology, []), :messaging_enabled, true)

      value ->
        parse_bool.(value)
    end,
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
    token: System.get_env("THREADR_DISCORD_TOKEN"),
    application_id: System.get_env("THREADR_DISCORD_APPLICATION_ID"),
    public_key: System.get_env("THREADR_DISCORD_PUBLIC_KEY"),
    allow_bot_messages: parse_bool.(System.get_env("THREADR_DISCORD_ALLOW_BOT_MESSAGES"))
  }

config :threadr,
       :control_plane_token,
       System.get_env("THREADR_CONTROL_PLANE_TOKEN") ||
         Application.get_env(:threadr, :control_plane_token)

config :threadr,
       :token_signing_secret,
       System.get_env("THREADR_TOKEN_SIGNING_SECRET") ||
         Application.get_env(:threadr, :token_signing_secret)

dispatcher_defaults =
  Application.get_env(:threadr, Threadr.ControlPlane.BotOperationDispatcher, [])

dispatcher_config =
  dispatcher_defaults
  |> Keyword.merge(
    enabled:
      case System.get_env("THREADR_BOT_OPERATION_DISPATCHER_ENABLED") do
        nil -> Keyword.get(dispatcher_defaults, :enabled)
        value -> parse_bool.(value)
      end,
    poll_interval_ms:
      parse_integer.(System.get_env("THREADR_BOT_OPERATION_DISPATCHER_POLL_INTERVAL_MS")) ||
        Keyword.get(dispatcher_defaults, :poll_interval_ms),
    batch_size:
      parse_integer.(System.get_env("THREADR_BOT_OPERATION_DISPATCHER_BATCH_SIZE")) ||
        Keyword.get(dispatcher_defaults, :batch_size),
    max_attempts:
      parse_integer.(System.get_env("THREADR_BOT_OPERATION_DISPATCHER_MAX_ATTEMPTS")) ||
        Keyword.get(dispatcher_defaults, :max_attempts),
    retry_backoff_ms:
      parse_integer.(System.get_env("THREADR_BOT_OPERATION_DISPATCHER_RETRY_BACKOFF_MS")) ||
        Keyword.get(dispatcher_defaults, :retry_backoff_ms)
  )

observer_defaults =
  Application.get_env(:threadr, Threadr.ControlPlane.BotStatusObserver, [])

observer_config =
  observer_defaults
  |> Keyword.merge(
    enabled:
      case System.get_env("THREADR_BOT_STATUS_OBSERVER_ENABLED") do
        nil -> Keyword.get(observer_defaults, :enabled)
        value -> parse_bool.(value)
      end,
    poll_interval_ms:
      parse_integer.(System.get_env("THREADR_BOT_STATUS_OBSERVER_POLL_INTERVAL_MS")) ||
        Keyword.get(observer_defaults, :poll_interval_ms),
    batch_size:
      parse_integer.(System.get_env("THREADR_BOT_STATUS_OBSERVER_BATCH_SIZE")) ||
        Keyword.get(observer_defaults, :batch_size)
  )

reconciler_defaults =
  Application.get_env(:threadr, Threadr.ControlPlane.KubernetesBotReconciler, [])

reconciler_config =
  reconciler_defaults
  |> Keyword.merge(
    default_image:
      System.get_env("THREADR_BOT_DEFAULT_IMAGE") ||
        Keyword.get(reconciler_defaults, :default_image),
    container_name:
      System.get_env("THREADR_BOT_CONTAINER_NAME") ||
        Keyword.get(reconciler_defaults, :container_name)
  )

config :threadr, Threadr.ControlPlane.BotOperationDispatcher, dispatcher_config
config :threadr, Threadr.ControlPlane.BotStatusObserver, observer_config
config :threadr, Threadr.ControlPlane.KubernetesBotReconciler, reconciler_config

ml_embeddings_config =
  Application.get_env(:threadr, Threadr.ML, [])
  |> Keyword.get(:embeddings, [])
  |> Keyword.merge(
    provider:
      normalize_module.(System.get_env("THREADR_EMBEDDINGS_PROVIDER")) ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:embeddings, []),
          :provider
        ),
    model:
      System.get_env("THREADR_EMBEDDINGS_MODEL") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:embeddings, []),
          :model
        ),
    document_prefix:
      System.get_env("THREADR_EMBEDDINGS_DOCUMENT_PREFIX") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:embeddings, []),
          :document_prefix
        ),
    query_prefix:
      System.get_env("THREADR_EMBEDDINGS_QUERY_PREFIX") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:embeddings, []),
          :query_prefix
        )
  )

ml_generation_config =
  Application.get_env(:threadr, Threadr.ML, [])
  |> Keyword.get(:generation, [])
  |> Keyword.merge(
    provider_name:
      env_or_legacy.("THREADR_SYSTEM_LLM_PROVIDER", "THREADR_GENERATION_PROVIDER_NAME") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :provider_name
        ),
    endpoint:
      env_or_legacy.("THREADR_SYSTEM_LLM_ENDPOINT", "THREADR_GENERATION_ENDPOINT") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :endpoint
        ),
    provider:
      normalize_module.(env_or_legacy.("THREADR_SYSTEM_LLM_ADAPTER", "THREADR_GENERATION_PROVIDER")) ||
        case Threadr.ML.Generation.ProviderResolver.resolve(
               env_or_legacy.("THREADR_SYSTEM_LLM_PROVIDER", "THREADR_GENERATION_PROVIDER_NAME") ||
                 Keyword.get(
                   Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
                   :provider_name
                 )
             ) do
          {:ok, provider} -> provider
          {:error, _reason} -> nil
        end ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :provider
        ),
    model:
      env_or_legacy.("THREADR_SYSTEM_LLM_MODEL", "THREADR_GENERATION_MODEL") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :model
        ),
    api_key:
      env_or_legacy.("THREADR_SYSTEM_LLM_API_KEY", "THREADR_GENERATION_API_KEY") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :api_key
        ),
    system_prompt:
      env_or_legacy.("THREADR_SYSTEM_LLM_SYSTEM_PROMPT", "THREADR_GENERATION_SYSTEM_PROMPT") ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :system_prompt
        ),
    temperature:
      parse_float.(env_or_legacy.("THREADR_SYSTEM_LLM_TEMPERATURE", "THREADR_GENERATION_TEMPERATURE")) ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :temperature
        ),
    max_tokens:
      parse_integer.(env_or_legacy.("THREADR_SYSTEM_LLM_MAX_TOKENS", "THREADR_GENERATION_MAX_TOKENS")) ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :max_tokens
        ),
    timeout:
      parse_integer.(env_or_legacy.("THREADR_SYSTEM_LLM_TIMEOUT_MS", "THREADR_GENERATION_TIMEOUT_MS")) ||
        Keyword.get(
          Application.get_env(:threadr, Threadr.ML, []) |> Keyword.get(:generation, []),
          :timeout
        )
  )

config :threadr, Threadr.ML,
  embeddings: ml_embeddings_config,
  generation: ml_generation_config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  db_ssl_enabled = parse_bool.(System.get_env("THREADR_DB_SSL"))

  db_ssl_verify =
    case System.get_env("THREADR_DB_SSL_VERIFY") do
      "verify_none" -> :verify_none
      _ -> :verify_peer
    end

  db_ssl_opts =
    case {db_ssl_enabled, System.get_env("THREADR_DB_SSL_CA_CERT_FILE")} do
      {false, _} ->
        []

      {true, nil} when db_ssl_verify == :verify_none ->
        [verify: :verify_none]

      {true, ""} when db_ssl_verify == :verify_none ->
        [verify: :verify_none]

      {true, nil} ->
        []

      {true, ""} ->
        []

      {true, ca_cert_file} ->
        [verify: db_ssl_verify, cacertfile: ca_cert_file]
    end

  config :threadr, Threadr.Repo,
    url: database_url,
    ssl: db_ssl_enabled,
    ssl_opts: db_ssl_opts,
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
