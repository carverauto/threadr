## Context
Threadr currently uses Go bots, Python processing services, Neo4j storage, and NATS JetStream for transport. Issue #128 proposes a ground-up rewrite in Elixir, but the draft PRD incorrectly frames JetStream as something that may be replaced by Phoenix PubSub or Elixir Registry. The intended direction is different: JetStream remains the durable cross-service event backbone, while Broadway becomes the standard consumption model inside the rewrite.

The rewrite is also expected to operate as a SaaS platform. Multiple tenants should share one CNPG PostgreSQL cluster and one Kubernetes namespace while keeping tenant data isolated. Tenants must be able to create and manage their own Threadr bots without requiring a separate deployment stack per customer.

## Goals
- Consolidate the primary runtime onto Elixir and the BEAM.
- Use Ash and AshPostgres to define application resources, actions, and data access patterns.
- Preserve a durable, replayable messaging backbone across ingestion and downstream processing.
- Replace Neo4j-centric storage with PostgreSQL plus graph, vector, temporal, and search extensions.
- Isolate tenant data with schema-based multitenancy on a shared PostgreSQL cluster.
- Support tenant-managed bot provisioning through a control plane.
- Provide authenticated web access for tenant users.
- Provide a public API for tenant automation and integrations.
- Let authenticated users create and revoke their own API keys.
- Standardize asynchronous processing around Broadway consumers.

## Non-Goals
- Replacing NATS JetStream with Phoenix PubSub alone.
- Keeping Python services in the core ingestion, inference, or retrieval path.
- Defining every implementation detail of specific Broadway producer libraries or adapters up front.
- Deploying one database instance per tenant.

## Architecture Decisions

### Ash Application Framework
Ash and AshPostgres are the primary application framework for the rewrite. Resources, actions, multitenancy rules, and resource relationships should be modeled in Ash instead of ad hoc Ecto contexts.

Phoenix and LiveView remain the user-facing web layer, but the business and persistence model should be centered on Ash domains and resources. AshPhoenix should be used where it reduces integration friction for forms, reads, and actions.

### Durable Messaging
NATS JetStream remains the system-of-record transport for normalized events. It provides durability, replay, back-pressure boundaries, and cross-service decoupling that Phoenix PubSub does not provide by itself.

Phoenix PubSub may still be used inside the Phoenix application for ephemeral fanout to LiveView processes or internal notifications, but it is not the replacement for the event backbone.

### Broadway Consumption Model
Broadway is the default pattern for asynchronous consumers in the rewrite. JetStream-backed workloads, such as embeddings, graph inference, summarization, and command handling, should be consumed through Broadway pipelines so the system can use batching, concurrency controls, acknowledgement handling, and demand-driven back-pressure.

This design intentionally leaves room for the implementation to choose the most suitable NATS or JetStream Broadway adapter, including a custom producer if needed.

### Data Platform
The rewrite replaces Neo4j with PostgreSQL using:
- Apache AGE for graph modeling and traversal
- pgvector for embeddings and similarity search
- TimescaleDB for temporal analytics and decay logic
- ParadeDB for full-text and keyword search

This keeps graph, vector, temporal, and search data in one operational store while preserving the graph-oriented use cases that Threadr depends on.

### Schema-Based Multitenancy
Tenant-owned graph and chat data live in tenant-specific PostgreSQL schemas on the shared CNPG cluster. This includes actors, channels, messages, relationships, embeddings, and similar analysis data.

The public schema stores control-plane resources that need cross-tenant visibility, such as tenants and bot definitions. Tenant creation should provision a new schema and run tenant migrations automatically through the AshPostgres multitenancy tooling.

### Control Plane
Threadr includes a control plane responsible for tenant lifecycle and bot lifecycle management. Tenants can create bot definitions through the application, and the control plane reconciles those definitions into Kubernetes resources in the shared namespace.

This control plane is part of the rewrite architecture, even if the first implementation slice only scaffolds the resource model and reconciliation boundary.

### Bot Lifecycle State Management
Bot lifecycle transitions are modeled as Ash state machines, not as raw attribute writes. Bot status changes such as `pending`, `reconciling`, `running`, `stopped`, `degraded`, `deleting`, and `error` must move through explicit Ash actions so the allowed transitions and side effects are declared in one place.

The control plane may still carry a separate `desired_state`, but any observed or in-flight lifecycle state that represents operational progress should be enforced by the Ash state machine. This keeps request handlers, async workers, and controller callbacks from inventing their own transition rules.

### Controller-Owned Desired-State Contract
The control plane does not own Kubernetes readiness directly. Its job is to translate tenant bot definitions into a concrete desired-state document that a Kubernetes controller can own.

That contract should be explicit and durable:
- the reconciler emits a versioned desired-state document for each bot workload
- the desired-state document is a concrete Kubernetes custom resource contract, not an app-private JSON wrapper
- the document includes stable bot identity, tenant identity, deployment identity, generation, and the rendered workload spec the controller is expected to realize
- the controller reports observed status back through a machine-authenticated callback that includes the contract generation it is reporting on

This separates three concerns cleanly:
1. the application owns user intent and desired state
2. a cluster-side sync component consumes the durable desired-state contracts and applies them as `ThreadrBot` custom resources
3. the Kubernetes controller owns realization of those `ThreadrBot` resources
4. status callbacks and polling only report observed progress against a specific desired generation

### Authenticated Tenant Access
The rewrite includes first-class user authentication for the web UI. Tenant users need a real sign-in flow and authenticated session model before the control plane or analyst UI can be treated as a SaaS product.

Authentication and authorization should stay aligned with the Ash-centered application model so user, membership, and policy rules are not split across ad hoc controller logic.

### Public API And API Keys
Threadr exposes a public API for tenant-facing automation, bot management, and future integration points. This API is separate from internal operational endpoints and is intended for direct customer use.

Authenticated users can mint and revoke their own API keys. API keys should be treated as credentials, shown in full only at creation time, and validated server-side without storing plaintext secrets.

### Runtime Consolidation
Elixir services handle ingestion, workflow orchestration, graph inference, user-facing APIs, and control-plane orchestration. Jido remains a candidate for agent-oriented orchestration, while local ML execution should remain flexible enough to compare Nx or Bumblebee with focused extraction models such as GLiNER2.

The current assumption should be:
- Nx or Bumblebee remain the leading candidates for fully Elixir-native embeddings and other BEAM-hosted inference
- GLiNER2 is an explicit candidate for schema-based information extraction, classification, and relation-oriented extraction if it proves more capable than a pure Nx or Bumblebee path for those workloads
- the rewrite may use one stack or a hybrid split, as long as Python is not reintroduced into the critical path without an explicit architectural decision

This keeps the architecture honest about an unresolved capability question: the team has not yet proven that a single local model stack is the best fit for both embeddings and structured extraction.

### Graph Exploration Rendering Pipeline
Threadr graph exploration should not introduce a second frontend graph stack. The rewrite should reuse the proven ServiceRadar God-View architecture where it fits the product:
- versioned binary snapshot transport using Apache Arrow IPC payloads
- compact roaring bitmap side metadata for high-cardinality visual class filters
- `deck.gl` as the primary graph renderer, targeting WebGPU-capable clients first
- a Wasm client compute layer for hot-path mask, traversal, and interpolation work

The Threadr graph domain is different from infrastructure topology, so the snapshot schema will be Threadr-specific, but the transport shape and performance model should be the same. The BEAM and PostgreSQL own graph state and query orchestration, while Rust or Wasm-backed components own dense binary packing and local high-volume client compute.

This avoids building:
1. one stack for analyst QA and another for graph exploration
2. one binary/GPU path in ServiceRadar and a weaker JSON/SVG path in Threadr
3. a LiveView graph page that becomes a migration burden when large tenants arrive

The initial graph exploration contract should therefore assume:
- authenticated tenant-scoped snapshot access
- a stable snapshot schema version with explicit node and edge column requirements
- bitmap-backed class filters and neighborhood masks for interactive graph navigation
- `deck.gl` layer composition instead of bespoke DOM rendering
- a documented fallback mode when WebGPU or Wasm is unavailable

## Risks And Mitigations
- Ash adoption changes the persistence model and developer workflow materially.
  Mitigation: adopt Ash early in the rewrite instead of migrating to it later, and keep resources aligned with the control-plane versus tenant-data boundary from the beginning.
- Broadway plus JetStream integration may require custom adapter work.
  Mitigation: treat the producer integration as an implementation detail and validate it early with a thin end-to-end spike.
- Apache AGE support through Ecto is less direct than first-party relational support.
  Mitigation: isolate AGE access behind explicit query modules and validate Cypher execution patterns before broader schema work.
- Schema multitenancy introduces migration and operational complexity.
  Mitigation: keep public control-plane resources separate from tenant-owned schemas and automate tenant schema creation and migration through the application stack.
- Bot lifecycle can become inconsistent if services, workers, and controllers mutate status directly.
  Mitigation: enforce lifecycle rules with Ash state machines and route all operational state updates through explicit resource actions.
- Public API access expands the security boundary materially.
  Mitigation: model user identity, tenant membership, and API key ownership as first-class resources, keep keys scoped to authenticated users, and store only non-recoverable credential material.
- Controller callbacks can become stale or race newer desired-state updates.
  Mitigation: version the desired-state contract with generations and reject stale controller reports that do not match the current desired generation.
- Running local ML workloads on the BEAM can create resource pressure.
  Mitigation: use Nx.Serving, batching, and dedicated worker configuration for embedding and LLM-serving paths.
- Locking local ML too early could force the wrong model stack onto both embeddings and extraction workloads.
  Mitigation: explicitly evaluate Nx/Bumblebee and GLiNER2 against the rewrite's embedding, entity extraction, and relation extraction needs before finalizing the serving model.
