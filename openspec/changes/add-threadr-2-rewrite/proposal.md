# Change: Define the Threadr 2.0 rewrite architecture

## Why
Issue #128 introduces the Threadr 2.0 rewrite direction, but its PRD incorrectly suggests that Threadr may stop using NATS JetStream. That is not the intended architecture. The rewrite should preserve JetStream as the durable event backbone and standardize downstream message handling around Broadway consumers.

The rewrite also needs a first-class SaaS architecture. Threadr must support many tenants sharing one CNPG PostgreSQL cluster while isolating tenant data with schema-based multitenancy, and tenants must be able to provision and manage their own bots through a control plane.

The SaaS rewrite also needs a first-class user access model. Tenant users need an authenticated web experience, a public API for automation and integrations, and a way for signed-in users to mint and revoke their own API keys without operator intervention.

## What Changes
- Define Threadr 2.0 as a BEAM-native rewrite centered on Elixir, Phoenix, LiveView, Ash, and a local-model strategy that evaluates Nx/Bumblebee alongside candidate extraction models such as GLiNER2.
- Preserve NATS JetStream as the durable transport for normalized chat events and asynchronous workloads.
- Establish Broadway-based consumers as the default message processing pattern for embeddings, graph inference, summarization, and similar pipelines.
- Establish Ash and AshPostgres as the primary application and data modeling framework.
- Use schema-based multitenancy on a shared CNPG PostgreSQL cluster for tenant-isolated Threadr data.
- Introduce public control-plane resources for tenant lifecycle and tenant-managed bot provisioning.
- Define authenticated web access so tenant users can sign in to the Threadr UI.
- Define a public API surface for tenant-facing automation and integrations.
- Define self-service API key management so authenticated users can create and revoke their own credentials.
- Define bot lifecycle transitions through Ash state machines instead of ad hoc status mutation.
- Define an explicit controller-owned desired-state contract for bot workloads and a machine-authenticated status callback path.
- Keep local ML backend selection open long enough to compare Nx/Bumblebee and GLiNER2 for the rewrite's actual embedding and schema-based extraction needs, rather than prematurely locking the design to one stack.
- Define PostgreSQL with Apache AGE, pgvector, TimescaleDB, and ParadeDB as the replacement for Neo4j and other specialized stores.
- Capture the rewrite scope in an approved OpenSpec change so later implementation work can proceed against a corrected architecture.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: future Elixir/Phoenix application code, Ash domains and resources, Ash state machine actions, authentication and session flows, public API endpoints, tenant schema migrations, NATS subjects and streams, ingestion adapters, graph and embedding pipelines, Kubernetes control-plane code, controller contract endpoints, and deployment manifests
