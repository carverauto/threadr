# Threadr 2.0 Rewrite Scaffold

This subtree is the initial Phoenix and Broadway foundation for the Threadr 2.0 rewrite.

## What Exists

- Phoenix LiveView application scaffold
- Ash, AshPostgres, and AshPhoenix foundations for the rewrite
- `NATS JetStream` topology config for normalized events
- `Broadway` pipeline wired to `OffBroadway.Jetstream.Producer`
- public-schema control-plane resources for tenants and bots
- durable public-schema bot reconciliation outbox records
- public-schema auth resources for users, tenant memberships, session tokens, and API keys
- tenant-schema resources for actors, channels, messages, mentions, relationships, and message embeddings
- `Threadr.ControlPlane.Service` for tenant provisioning and bot reconciliation entrypoints
- canonical event types for:
  - chat messages
  - ingest commands
  - processing results
- `mix threadr.nats.setup` to provision the initial JetStream stream and consumer
- `mix threadr.smoke.ingest` to publish a tenant-scoped chat event and verify Broadway persistence
- `mix threadr.smoke.bot_contract` to create a control-plane bot and emit a real `ThreadrBot` contract for operator smoke testing
- `mix threadr.smoke.operator` to run the Phoenix and Go operator smoke flow end to end

## Event Subjects

- `threadr.tenants.<tenant-subject>.chat.message`
- `threadr.tenants.<tenant-subject>.ingest.command`
- `threadr.tenants.<tenant-subject>.processing.result`

These roll up under the `THREADR_EVENTS` stream by default via `threadr.tenants.>`.

## Local Development

Start the local infrastructure stack:

```bash
cd elixir/threadr
docker compose up -d
```

Then export the local env values or load them from `.env.local.example`:

```bash
cd elixir/threadr
export THREADR_DB_HOST=localhost
export THREADR_DB_PORT=55432
export THREADR_DB_USER=postgres
export THREADR_DB_PASSWORD=postgres
export THREADR_DB_NAME=threadr_dev
export THREADR_TEST_DB_NAME=threadr_test
export THREADR_NATS_HOST=localhost
export THREADR_NATS_PORT=54222
```

Then initialize the app databases:

```bash
cd elixir/threadr
mix ecto.create
mix ecto.migrate
```

The public migrations enable `age`, `vector`, `timescaledb`, and opportunistically enable `pg_search` when the image provides it, so the database must be backed by the CNPG image or another Postgres build that includes those extensions.

Tenant-owned tables live in `priv/repo/tenant_migrations`, which AshPostgres uses when provisioning or migrating tenant schemas.

Start or point at a NATS server with JetStream enabled, then provision the topology:

```bash
cd elixir/threadr
mix threadr.nats.setup
```

Run the end-to-end local smoke check:

```bash
cd elixir/threadr
mix threadr.smoke.ingest --tenant-name "Acme Threat Intel" --mentions bob,carol
```

Provision a real control-plane bot contract for the operator smoke path:

```bash
cd elixir/threadr
mix threadr.smoke.bot_contract --tenant-subject threadr-smoke --bot-name irc-main
```

That prints the tenant subject, bot id, deployment name, and machine-authenticated contract URL for the created or reused bot.

Run the full Phoenix and Go operator smoke flow:

```bash
cd elixir/threadr
mix threadr.smoke.operator --tenant-subject threadr-smoke --bot-name irc-main
```

That provisions a control-plane contract, boots a temporary Phoenix server, runs `go run ./cmd/threadrbot-smoke` against the machine-authenticated contract feed, and verifies the controller callback updated the bot row for the current generation.

The same flow is now wired into GitHub Actions through [threadr-operator-smoke.yml](/Users/mfreeman/src/threadr/.github/workflows/threadr-operator-smoke.yml#L1), scoped to changes under `elixir/threadr` and `k8s/operators/ircbot-operator`.

Upgrade existing tenant schemas after adding new tenant migrations:

```bash
cd elixir/threadr
mix threadr.tenants.migrate --all
```

Run the gated ExUnit integration test against the same local stack:

```bash
cd elixir/threadr
THREADR_RUN_INTEGRATION=true mix test test/threadr/messaging/smoke_test.exs
```

Enable the Broadway consumer and start Phoenix:

```bash
cd elixir/threadr
THREADR_BROADWAY_ENABLED=true mix phx.server
```

Then use the new auth and account surfaces:

- Web sign-in: `http://localhost:4000/sign-in`
- Registration: `http://localhost:4000/register`
- Tenant control plane: `http://localhost:4000/control-plane/tenants`
- Personal API keys: `http://localhost:4000/settings/api-keys`
- Public API examples:
  - `GET /api/v1/bot-platforms`
  - `GET /api/v1/me`
  - `GET /api/v1/tenants`
  - `POST /api/v1/tenants`
  - `POST /api/v1/tenants/:subject_name/migrate`
  - `GET /api/v1/tenants/:subject_name/bots`
  - `POST /api/v1/tenants/:subject_name/bots`
  - `PATCH /api/v1/tenants/:subject_name/bots/:id`
  - `DELETE /api/v1/tenants/:subject_name/bots/:id`
  - `GET /api/v1/tenants/:subject_name/memberships`
  - `POST /api/v1/tenants/:subject_name/memberships`
  - `PATCH /api/v1/tenants/:subject_name/memberships/:id`
  - `DELETE /api/v1/tenants/:subject_name/memberships/:id`

## Runtime Configuration

- `THREADR_NATS_HOST` defaults to `localhost`
- `THREADR_NATS_PORT` defaults to `4222`
- `THREADR_BROADWAY_ENABLED=true` starts the Broadway JetStream consumer
- `THREADR_INGEST_ENABLED=true` starts a single-platform bot ingest runtime inside the pod
- `THREADR_PLATFORM` supports `irc` and `discord`
- `THREADR_IRC_SSL=true` enables TLS for IRC connections, which is typically required on `6697`
- `THREADR_TOKEN_SIGNING_SECRET` should be set in real environments; local dev falls back to a static dev secret
- `THREADR_CONTROL_PLANE_TOKEN` should be set for machine-to-machine controller callbacks
- `Threadr.ControlPlane.BotOperationDispatcher` drains pending bot reconciliation operations asynchronously
- dispatcher retries failed reconciliation attempts according to `max_attempts` and `retry_backoff_ms`
- `Threadr.ControlPlane.KubernetesBotReconciler` now emits a concrete `ThreadrBot` custom resource contract that a Kubernetes controller can own
- `Threadr.ControlPlane.BotStatusObserver` can be enabled to poll Deployment readiness and move bots from `reconciling` to `running`, `stopped`, `degraded`, or `error`
- `:command_executor` defaults to `Threadr.Commands.NoopExecutor`, which marks commands as succeeded until platform-specific executors are added

## Ingest Runtime

Each bot pod can now run a single ingest runtime that normalizes upstream chat
messages into tenant-scoped `chat.message` events on JetStream.

The control plane already injects these base env vars into the bot workload:

- `THREADR_INGEST_ENABLED=true`
- `THREADR_BOT_ID`
- `THREADR_TENANT_ID`
- `THREADR_TENANT_SUBJECT`
- `THREADR_PLATFORM`
- `THREADR_CHANNELS`

Platform credentials and connection details should be supplied through
`bot.settings["env"]`. The public bot API now normalizes legacy top-level
platform keys into that env map automatically. For example, an IRC bot create
request can still send `settings.server` and `settings.nick`, but the stored
shape becomes:

```json
{
  "settings": {
    "env": {
      "THREADR_IRC_HOST": "irc.example.com",
      "THREADR_IRC_NICK": "threadr-bot"
    }
  }
}
```

Sensitive env values like `THREADR_IRC_PASSWORD` and `THREADR_DISCORD_TOKEN`
are redacted in API responses, but retained in the persisted bot definition and
controller contract.

For IRC pods, set:

- `THREADR_IRC_HOST`
- `THREADR_IRC_PORT` such as `6667` or `6697`
- `THREADR_IRC_SSL=true` when using TLS
- `THREADR_IRC_NICK`
- optional `THREADR_IRC_USER`
- optional `THREADR_IRC_REALNAME`
- optional `THREADR_IRC_PASSWORD`

The IRC runtime uses `ExIRC` and joins the configured `THREADR_CHANNELS` on
successful logon.

For Discord pods, set:

- `THREADR_DISCORD_TOKEN`

The Discord runtime uses `Nostrum`, but the dependency is started on demand only
when `THREADR_PLATFORM=discord`, so the Phoenix app no longer requires a
Discord token just to boot.

## Multitenancy Shape

- `public` schema: tenants and bot control-plane records
- tenant schemas: actors, channels, messages, mentions, relationships, and embeddings

Tenant subject scoping uses the tenant `subject_name`, not the tenant UUID. The token is derived from the slug using only NATS-safe characters (`A-Z`, `a-z`, `0-9`, `_`, `-`).

The intended deployment model is many Threadr tenants sharing one CNPG cluster and one Kubernetes namespace, with tenant-created bot definitions reconciled by the control plane.

Bot lifecycle operations now emit durable `bot_reconcile_operations` rows, and the supervised `Threadr.ControlPlane.BotOperationDispatcher` drains them asynchronously with scheduled retries. That gives the future Kubernetes controller a stable handoff record for `apply` and `delete` intents instead of relying on in-memory side effects.

The current reconciler persists a concrete `ThreadrBot` custom resource document in the control plane. That document is available through the machine-authenticated `/api/control-plane/bot-contracts` endpoints and is shaped to match the Kubebuilder CRD under [cache.threadr.ai_threadrbots.yaml](/Users/mfreeman/src/threadr/k8s/operators/ircbot-operator/config/crd/bases/cache.threadr.ai_threadrbots.yaml). By default it uses the placeholder image `threadr-bot:latest`; production deployments should override that with `bot.settings["image"]` or a reconciler config override.

Apply success no longer implies health. Bot create and update operations stay `reconciling` until `Threadr.ControlPlane.BotStatusObserver` confirms the Deployment state from Kubernetes. The observer is disabled by default in local dev and can be enabled with:

```elixir
config :threadr, Threadr.ControlPlane.BotStatusObserver,
  enabled: true,
  poll_interval_ms: 15_000
```

For controller-driven status updates, the app now exposes a machine-authenticated callback:

```http
POST /api/control-plane/tenants/:subject_name/bots/:id/status
Authorization: Bearer $THREADR_CONTROL_PLANE_TOKEN
Content-Type: application/json

{
  "status": {
    "status": "running",
    "reason": "deployment_available",
    "deployment_name": "threadr-acme-irc-main",
    "observed_at": "2026-03-05T23:59:00Z",
    "metadata": {
      "ready_replicas": 1,
      "available_replicas": 1
    }
  }
}
```

The callback updates `status`, `status_reason`, `status_metadata`, and `last_observed_at` on the bot row, and rejects stale deployment names so an old rollout cannot overwrite a newer workload state.

When the controller reports terminal `deleted` status for the current generation, the control plane finalizes the bot lifecycle through the Ash state machine and destroys the public bot record. The next contract sync cycle then removes the orphaned `ThreadrBot` CR from Kubernetes.

The controller contract endpoints expose the current desired-state CR documents directly:

```http
GET /api/control-plane/bot-contracts
GET /api/control-plane/tenants/:subject_name/bots/:id/contract
Authorization: Bearer $THREADR_CONTROL_PLANE_TOKEN
```

Each response contains a `contract` payload shaped as a `cache.threadr.ai/v1alpha1` `ThreadrBot` resource, including the control-plane generation in `spec.controlPlane.generation`.

The cluster-side sync component is expected to consume those endpoints with:

- `THREADR_CONTROL_PLANE_BASE_URL`
- `THREADR_CONTROL_PLANE_TOKEN`
- `THREADR_CONTROL_PLANE_SYNC_INTERVAL` such as `15s`

The connection starts under `Threadr.Messaging.Supervisor`. The Broadway pipeline is opt-in so the app can boot before the stream and durable consumer exist.

The current control-plane entrypoints are:

```elixir
Threadr.ControlPlane.Service.create_tenant(%{name: "Acme"})
Threadr.ControlPlane.Service.create_bot(%{tenant_id: tenant.id, name: "irc-main", platform: "irc"})
Threadr.ControlPlane.Service.update_bot_for_user(user, tenant.subject_name, bot.id, %{desired_state: "stopped"})
Threadr.ControlPlane.Service.create_tenant_membership_for_user(user, tenant.subject_name, %{email: "analyst@example.com", role: "member"})
```

The auth entrypoints are:

```elixir
Threadr.ControlPlane.register_user(%{
  email: "analyst@example.com",
  name: "Analyst",
  password: "threadr-password"
})

{:ok, api_key, plaintext_api_key} =
  Threadr.ControlPlane.Service.create_api_key(user, %{name: "CI"})
```

Tenant and bot operations are now membership-aware:

- any authenticated user can create a tenant and becomes its `owner`
- tenant `owner` and `admin` roles can migrate tenants, create or update bots, and manage tenant memberships
- tenant `member` roles can read tenant-scoped API data but cannot run management actions
