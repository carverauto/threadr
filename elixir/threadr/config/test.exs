import Config

integration_enabled = System.get_env("THREADR_RUN_INTEGRATION") in ~w(true 1 TRUE)

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :threadr, Threadr.Repo,
  username: System.get_env("THREADR_DB_USER") || "postgres",
  password: System.get_env("THREADR_DB_PASSWORD") || "postgres",
  hostname: System.get_env("THREADR_DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("THREADR_DB_PORT") || "55432"),
  database:
    System.get_env("THREADR_TEST_DB_NAME") ||
      "threadr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :threadr, ThreadrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Ra+Va+w1RpDazkfAcYuVBprPYD9IKam0DDnYeYJa82aiF4HIoVKnn4n6qld0d4mY",
  server: false

# In test we don't send emails
config :threadr, Threadr.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :threadr, Threadr.ML,
  embeddings: [
    provider: Threadr.ML.Embeddings.HashProvider,
    model: "term-hash-384-v1",
    document_prefix: "passage: ",
    query_prefix: "query: "
  ],
  extraction: [
    enabled: true,
    provider: Threadr.ML.Extraction.NoopProvider,
    provider_name: "openai",
    system_prompt: nil,
    temperature: 0.0,
    max_tokens: 600,
    timeout: 30_000
  ]

config :threadr, Threadr.Messaging.Topology, messaging_enabled: integration_enabled

config :threadr, Threadr.ControlPlane.BotOperationDispatcher, enabled: false
config :threadr, Threadr.ControlPlane.BotStatusObserver, enabled: false
