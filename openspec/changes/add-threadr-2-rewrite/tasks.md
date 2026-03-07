## 1. Foundation
- [x] 1.1 Bootstrap the Elixir/Phoenix application structure for Threadr 2.0.
- [x] 1.2 Integrate Ash, AshPostgres, and AshPhoenix as the primary application framework.
- [x] 1.3 Provision PostgreSQL through the CNPG image with Apache AGE, pgvector, TimescaleDB, and ParadeDB enabled.
- [x] 1.4 Define public-schema control-plane resources for tenants and bot lifecycle management.
- [x] 1.5 Define tenant-schema resources and migrations for actors, channels, messages, relationships, and embeddings.
- [x] 1.6 Configure schema-based multitenancy so tenant creation provisions and migrates a new PostgreSQL schema.
- [x] 1.7 Model bot lifecycle with Ash state machines and explicit transition actions.

## 2. Messaging And Ingestion
- [x] 2.1 Define the canonical normalized event schema for chat messages, commands, and processing results.
- [x] 2.2 Provision NATS JetStream streams and subjects required by the rewrite.
- [x] 2.3 Implement Broadway pipelines that consume JetStream-backed workloads with batching, back-pressure, and retry semantics.
- [x] 2.4 Build IRC and Discord ingestion agents that publish normalized events into JetStream.

## 3. Processing And Graph Workflows
- [x] 3.1 Evaluate and implement Elixir-owned ML execution for embeddings and schema-based extraction, using BEAM-native runtimes where appropriate and remote providers only through Elixir.
- [x] 3.1.a Implement provider-neutral embedding and generation boundaries, including Bumblebee-backed embeddings and pluggable remote generation providers.
- [x] 3.1.b Implement tenant-scoped semantic retrieval, Graph-RAG, summarization, and public or LiveView QA surfaces on top of those ML boundaries.
- [x] 3.1.c Implement a concrete Elixir-owned structured-extraction strategy for schema-based extraction and tenant-scoped persistence, without introducing Python workers.
- [x] 3.2 Implement graph inference and relationship updates against Apache AGE in PostgreSQL.
- [x] 3.3 Implement Graph-RAG and summarization workflows without Python services in the critical path.

## 4. UI And Operations
- [x] 4.1 Build Phoenix LiveView interfaces for chat history, dossiers, and graph exploration, using the binary Arrow plus roaring bitmap plus `deck.gl` plus Wasm pipeline for graph exploration.
- [x] 4.1.a Build authenticated tenant QA and graph exploration LiveViews, including the binary Arrow plus roaring bitmap plus `deck.gl` plus Wasm graph pipeline.
- [x] 4.1.b Build analyst-facing chat history and dossier LiveViews that expose temporal conversation context outside the current QA and graph exploration surfaces.
- [x] 4.1.c Finish the graph investigation workflow polish so the graph starts from channel overviews, drills into conversation and message neighborhoods, and keeps selection details in the dedicated side panel.
- [x] 4.2 Implement authenticated web sign-in and tenant-scoped session handling for the Threadr UI.
- [x] 4.3 Implement self-service API key creation, listing, and revocation for authenticated users.
- [x] 4.4 Define the first public API surface for tenant-facing automation and control-plane access.
- [x] 4.5 Define deployment, observability, Bazel-driven image delivery, and operational guidance for the rewrite components.
- [x] 4.6 Implement or scaffold the Kubernetes control-plane boundary that reconciles tenant bot definitions into bot workloads in the shared namespace.
- [x] 4.7 Define and persist a controller-owned `ThreadrBot` custom resource contract for bot workloads, with generation-aware status callbacks.
- [x] 4.8 Verify end-to-end ingestion through JetStream, Broadway consumers, PostgreSQL persistence, and LiveView updates.
- [x] 4.8.a Verify end-to-end ingestion through JetStream, Broadway consumers, and PostgreSQL persistence, including IRC, Discord, duplicate-delivery, and operator-contract smoke coverage.
- [x] 4.8.b Add explicit automated verification that LiveView surfaces update from ingestion-driven state changes rather than only reading persisted state after the fact.
- [x] 4.8.c Re-run graph snapshot and tenant graph LiveView verification for the investigation workflow against a PostgreSQL-backed test environment and extend coverage for any uncovered regressions.
- [x] 4.9 Implement first-install operator-admin bootstrap, persisted operator-admin authorization, and forced password rotation for bootstrap credentials.
