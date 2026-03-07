# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :threadr,
  ecto_repos: [Threadr.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ash_domains: [Threadr.ControlPlane, Threadr.TenantData]

config :threadr, :bot_reconciler, Threadr.ControlPlane.KubernetesBotReconciler
config :threadr, :kubernetes_client, Threadr.ControlPlane.KubernetesReqClient
config :threadr, :command_executor, Threadr.Commands.NoopExecutor
config :threadr, :control_plane_token, "threadr-dev-control-plane-token"
config :threadr, :token_signing_secret, "threadr-dev-signing-secret-change-me"

config :threadr, Threadr.ControlPlane.BotOperationDispatcher,
  enabled: true,
  poll_interval_ms: 5_000,
  batch_size: 25,
  max_attempts: 3,
  retry_backoff_ms: 5_000

config :threadr, Threadr.ControlPlane.BotStatusObserver,
  enabled: false,
  poll_interval_ms: 15_000,
  batch_size: 50

config :threadr, Threadr.ControlPlane.KubernetesBotReconciler,
  default_image: "threadr-bot:latest",
  container_name: "threadr-bot"

config :threadr, Threadr.Ingest,
  enabled: false,
  platform: nil,
  tenant_subject_name: nil,
  tenant_id: nil,
  bot_id: nil,
  channels: [],
  publisher: Threadr.Messaging.Publisher,
  irc: %{
    host: nil,
    port: 6667,
    ssl: false,
    nick: nil,
    user: nil,
    realname: "Threadr Bot",
    password: nil
  },
  discord: %{
    token: nil,
    application_id: nil,
    public_key: nil,
    allow_bot_messages: false
  }

config :threadr, Threadr.ML,
  embeddings: [
    provider: Threadr.ML.Embeddings.BumblebeeProvider,
    model: "intfloat/e5-small-v2",
    document_prefix: "passage: ",
    query_prefix: "query: "
  ],
  generation: [
    provider: Threadr.ML.Generation.NoopProvider,
    provider_name: "chat_completions",
    endpoint: "http://localhost:11434/v1/chat/completions",
    model: "llama3.1:8b-instruct",
    api_key: nil,
    system_prompt: nil,
    temperature: nil,
    max_tokens: nil,
    timeout: 30_000
  ]

config :threadr, Threadr.Messaging.Topology,
  messaging_enabled: true,
  connection_name: :threadr_gnat,
  connection_retry_backoff: 2_000,
  pipeline_enabled: false,
  broadway: [
    producer_concurrency: 1,
    processor_concurrency: 4,
    receive_interval: 1_000,
    receive_timeout: 1_000,
    batch_size: 25,
    batch_timeout: 1_000
  ],
  connections: [
    %{host: "localhost", port: 4222}
  ],
  stream_name: "THREADR_EVENTS",
  consumer_name: "THREADR_REWRITE",
  subjects: %{
    tenant_wildcard: "threadr.tenants.>",
    chat_messages: "chat.message",
    ingest_commands: "ingest.command",
    processing_results: "processing.result"
  }

# Configures the endpoint
config :threadr, ThreadrWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThreadrWeb.ErrorHTML, json: ThreadrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Threadr.PubSub,
  live_view: [signing_salt: "smamUKDE"]

config :threadr, Threadr.Repo, types: Threadr.PostgresTypes

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :threadr, Threadr.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  threadr: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  threadr: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
