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
- `mix threadr.smoke.discord` to wait for a real Discord gateway `READY` event from the ingest runtime
- `mix threadr.embeddings.generate` to generate and publish a local `processing.result` embedding event for an existing tenant message
- `mix threadr.generation.complete` to run a prompt through the configured generation provider boundary
- `mix threadr.generation.answer` to run question-answering against explicit context through the same provider boundary
- `mix threadr.generation.answer_tenant` to retrieve tenant message context by vector similarity and answer against it
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

Seed a tenant with realistic demo chat history and inline embeddings for the QA UI:

```bash
cd elixir/threadr
mix threadr.seed.demo --tenant-subject carverauto
```

That leaves the selected tenant ready for semantic search in the QA workspace.
Development defaults to the deterministic
`Threadr.ML.Embeddings.HashProvider`, so the seed finishes quickly and the QA
workspace can search immediately. Set `THREADR_EMBEDDINGS_PROVIDER` if you want
to force `Threadr.ML.Embeddings.BumblebeeProvider` instead.

Bootstrap the first operator-admin account on a fresh install:

```bash
cd elixir/threadr
mix threadr.bootstrap.operator_admin \
  --email admin@example.com \
  --name "Platform Admin" \
  --secret-name threadr-bootstrap-admin \
  --namespace threadr
```

That creates the first persisted operator-admin only when none exists, prints the
temporary bootstrap password once, and can emit a Kubernetes `Secret` manifest for
install-time automation. Bootstrap users are forced to rotate that password at
first sign-in before they can use the control plane.

For Kubernetes installs, a Kustomize-native control-plane base is included under
[k8s/threadr/control-plane/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/kustomization.yaml#L1).
It includes:
- a `Deployment` and `Service` for the Phoenix control plane
- a default `Ingress` for the web surface
- a migration init container that runs `bin/threadr eval 'Threadr.ReleaseTasks.migrate()'`
- a bootstrap `Job` that creates or reuses the `threadr-bootstrap-admin` Secret and then bootstraps the first operator admin
- HTTP health probes on `/health/live` and `/health/ready`
- Prometheus-style metrics on `/metrics`

That base expects:
- a real control-plane release image instead of the placeholder `threadr-control-plane:latest`
- a runtime env Secret named `threadr-control-plane-env` with at least `DATABASE_URL`, `SECRET_KEY_BASE`, and the normal production env required by `runtime.exs`
- `THREADR_BOOTSTRAP_ADMIN_EMAIL` set in `threadr-bootstrap-admin-config`

An example runtime Secret is included at
[control-plane-env-secret.example.yaml](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/control-plane-env-secret.example.yaml#L1).

Apply it with Kustomize after setting those values:

```bash
kubectl apply -k k8s/threadr/control-plane
```

The rendered Service is named `threadr-control-plane`, and the base defaults
`PHX_HOST` to `threadr-control-plane.threadr.svc.cluster.local`.
The default ingress host is `threadr.local`; patch
[ingress.yaml](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/ingress.yaml#L1)
or override it in your environment-specific Kustomize layer.

The service is annotated for scrape-by-annotation Prometheus setups, and the
application exports metrics at `GET /metrics`. Health probes use:
- `GET /health/live`
- `GET /health/ready`

Optional overlays are included for more opinionated clusters:
- TLS ingress overlay:
  [overlays/nginx-tls/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/nginx-tls/kustomization.yaml#L1)
- Prometheus Operator overlay:
  [overlays/prometheus-servicemonitor/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/prometheus-servicemonitor/kustomization.yaml#L1)
- Restricted network policy overlay:
  [overlays/restricted-network/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/restricted-network/kustomization.yaml#L1)

Example:

```bash
kubectl apply -k k8s/threadr/overlays/control-plane/nginx-tls
kubectl apply -k k8s/threadr/overlays/control-plane/prometheus-servicemonitor
kubectl apply -k k8s/threadr/overlays/control-plane/restricted-network
```

The control-plane image is published to
`ghcr.io/carverauto/threadr/threadr-control-plane` through
[threadr-control-plane-image.yml](/Users/mfreeman/src/threadr/.github/workflows/threadr-control-plane-image.yml#L1).
The image override overlay for GHCR is
[ghcr/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/ghcr/kustomization.yaml#L1).
The canonical Bazel entrypoints are split by environment:

```bash
bazel build -c opt //elixir/threadr:release_tar --config=remote
bazel build -c opt //docker/images:control_plane_image_amd64 --config=remote
```

Use the remote build targets above from local macOS development. The push target
is intentionally treated as a Linux CI path, because `bazel run` executes the
generated push script on the host and the current `rules_oci` helper resolution
is not portable for local macOS push execution.

The canonical push path is the GitHub workflow on Linux. Only `main` publishes
and updates the production digest pin:

```bash
bazel run -c opt //docker/images:push_all --config=remote
```

If `BUILDBUDDY_API_KEY` is configured in GitHub Actions, the workflow uses
BuildBuddy RBE. If it is not configured, the same workflow falls back to local
execution on the Linux GitHub runner.

On `main`, the image publish workflow also resolves the pushed GHCR digest and
commits it back into
[image-patch.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/production/image-patch.yaml#L1),
so the production overlay stays pinned to an immutable image reference without
manual manifest edits.

An ArgoCD `Application` manifest for the control plane is included at
[application.yaml](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/application.yaml#L1).
It points at the production overlay and enables automated sync with prune and self-heal.

The production overlay is
[production/kustomization.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/production/kustomization.yaml#L1).
It pins:
- the GHCR image digest
- the external hostname and TLS secret name
- the bootstrap operator email
- the observer-enabled control-plane config

The placeholder digest in
[image-patch.yaml](/Users/mfreeman/src/threadr/k8s/threadr/overlays/control-plane/production/image-patch.yaml#L1)
is expected to be replaced automatically by the image publish workflow on `main`.

Before syncing that overlay, create these Secrets in the `threadr` namespace:
- `threadr-control-plane-env`
- `threadr-control-plane-tls`

The runtime env Secret is now expected to be managed through Sealed Secrets.
Start from
[control-plane-env-secret.example.yaml](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/control-plane-env-secret.example.yaml#L1),
replace the placeholder values, and seal it with
[seal_control_plane_env.sh](/Users/mfreeman/src/threadr/k8s/threadr/control-plane/seal_control_plane_env.sh#L1):

```bash
./k8s/threadr/control-plane/seal_control_plane_env.sh \
  --input k8s/threadr/control-plane/control-plane-env-secret.example.yaml \
  --output k8s/threadr/control-plane/control-plane-env.sealedsecret.yaml
kubectl apply -f k8s/threadr/control-plane/control-plane-env.sealedsecret.yaml
```

That keeps plaintext production credentials out of Git while standardizing the
cluster-side secret source around the existing `sealed-secrets` controller.

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

Run the gated Discord runtime smoke check with a real bot token:

```bash
cd elixir/threadr
THREADR_INGEST_ENABLED=true \
THREADR_PLATFORM=discord \
THREADR_TENANT_SUBJECT=threadr-smoke \
THREADR_CHANNELS='["123456789"]' \
THREADR_DISCORD_APPLICATION_ID=... \
THREADR_DISCORD_PUBLIC_KEY=... \
THREADR_DISCORD_TOKEN=... \
mix threadr.smoke.discord
```

That waits for the ingest runtime to emit a Discord `READY` event and prints the
observed guild count and shard information.

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
- Password rotation: `http://localhost:4000/settings/password`
- Operator system LLM settings: `http://localhost:4000/control-plane/admin/llm`
- Tenant control plane: `http://localhost:4000/control-plane/tenants`
- Tenant graph workspace: `http://localhost:4000/control-plane/tenants/:subject_name/graph`
- Tenant QA workspace: `http://localhost:4000/control-plane/tenants/:subject_name/qa`
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
  - `POST /api/v1/tenants/:subject_name/qa/search`
  - `POST /api/v1/tenants/:subject_name/qa/answer`
  - `POST /api/v1/tenants/:subject_name/qa/graph-answer`
  - `POST /api/v1/tenants/:subject_name/qa/summarize`
  - `GET /api/v1/tenants/:subject_name/memberships`
  - `POST /api/v1/tenants/:subject_name/memberships`
  - `PATCH /api/v1/tenants/:subject_name/memberships/:id`
  - `DELETE /api/v1/tenants/:subject_name/memberships/:id`

The local dev server path is verified with:

```bash
cd elixir/threadr
THREADR_DB_HOST=localhost \
THREADR_DB_PORT=55432 \
THREADR_DB_USER=postgres \
THREADR_DB_PASSWORD=postgres \
THREADR_DB_NAME=threadr_dev \
THREADR_NATS_HOST=localhost \
THREADR_NATS_PORT=54222 \
THREADR_BROADWAY_ENABLED=true \
mix phx.server
```

That boots Phoenix with working Tailwind and esbuild watchers, so the graph and
QA workspaces are now testable in a real browser session.

## Runtime Configuration

- `THREADR_NATS_HOST` defaults to `localhost`
- `THREADR_NATS_PORT` defaults to `4222`
- `THREADR_BROADWAY_ENABLED=true` starts the Broadway JetStream consumer
- `THREADR_INGEST_ENABLED=true` starts a single-platform bot ingest runtime inside the pod
- `THREADR_PLATFORM` supports `irc` and `discord`
- `THREADR_IRC_SSL=true` enables TLS for IRC connections, which is typically required on `6697`
- `THREADR_TOKEN_SIGNING_SECRET` should be set in real environments; local dev falls back to a static dev secret
- `THREADR_CONTROL_PLANE_TOKEN` should be set for machine-to-machine controller callbacks
- the first operator-admin can be bootstrapped with `mix threadr.bootstrap.operator_admin`; repeated runs are intentionally no-ops once an operator-admin exists
- system LLM configuration is operator-admin only; tenant managers can only choose between `Use system provider` and `Use tenant override`
- `THREADR_EMBEDDINGS_PROVIDER`, `THREADR_EMBEDDINGS_MODEL`, and related embedding env vars control the local embedding backend
- `THREADR_SYSTEM_LLM_ADAPTER`, `THREADR_SYSTEM_LLM_PROVIDER`, `THREADR_SYSTEM_LLM_ENDPOINT`, `THREADR_SYSTEM_LLM_MODEL`, and `THREADR_SYSTEM_LLM_API_KEY` control the operator-managed default LLM backend
- `THREADR_SYSTEM_LLM_SYSTEM_PROMPT`, `THREADR_SYSTEM_LLM_TEMPERATURE`, `THREADR_SYSTEM_LLM_MAX_TOKENS`, and `THREADR_SYSTEM_LLM_TIMEOUT_MS` tune that backend without changing application call sites
- legacy `THREADR_GENERATION_*` env vars are still accepted as compatibility aliases, but the control-plane secret contract should use `THREADR_SYSTEM_LLM_*`
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
- optional `THREADR_DISCORD_APPLICATION_ID`
- optional `THREADR_DISCORD_PUBLIC_KEY`

The Discord runtime uses `Nostrum`, but the dependency is started on demand only
when `THREADR_PLATFORM=discord`, so the Phoenix app no longer requires a
Discord token just to boot.

## ML Boundaries

The rewrite now treats embeddings and general-purpose generation as separate
boundaries:

- `Threadr.ML.Embeddings` supports both document and query embeddings, and
  publishes message embeddings into the existing `processing.result` JetStream
  path
- `Threadr.ML.Generation` handles general prompt completion for future QA,
  summarization, and Graph-RAG flows
- `Threadr.ML.SemanticQA` combines tenant-scoped vector retrieval with the
  generic generation boundary for the first retrieval-plus-QA path
- `Threadr.ML.GraphRAG` layers Apache AGE-backed graph neighborhood retrieval on
  top of semantic matches for graph-aware answers and topic summaries

Embeddings default to `Threadr.ML.Embeddings.BumblebeeProvider` with
`intfloat/e5-small-v2`, but development overrides that with the deterministic
`Threadr.ML.Embeddings.HashProvider` for fast local QA and demo seeding.
Generation still defaults to the noop provider until a real backend is configured, for example
`Threadr.ML.Generation.ChatCompletionsProvider`.

The generation boundary is intentionally provider-agnostic. `Threadr.ML.Generation`
accepts a generic request struct and returns a generic result struct, while
`Threadr.ML.Generation.ChatCompletionsProvider` is just one adapter for
OpenAI-compatible APIs such as OpenAI, vLLM, Ollama, or similar endpoints.

The tenant QA workspace now supports four workflows from the same page:

- semantic search over embedded tenant messages
- grounded semantic QA
- graph-aware QA using AGE neighborhood context
- topic summarization over combined semantic and graph evidence

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
