## 1. Foundation
- [ ] 1.1 Bootstrap the Elixir/Phoenix application structure for Threadr 2.0.
- [ ] 1.2 Integrate Ash, AshPostgres, and AshPhoenix as the primary application framework.
- [ ] 1.3 Provision PostgreSQL through the CNPG image with Apache AGE, pgvector, TimescaleDB, and ParadeDB enabled.
- [ ] 1.4 Define public-schema control-plane resources for tenants and bot lifecycle management.
- [ ] 1.5 Define tenant-schema resources and migrations for actors, channels, messages, relationships, and embeddings.
- [ ] 1.6 Configure schema-based multitenancy so tenant creation provisions and migrates a new PostgreSQL schema.
- [ ] 1.7 Model bot lifecycle with Ash state machines and explicit transition actions.

## 2. Messaging And Ingestion
- [ ] 2.1 Define the canonical normalized event schema for chat messages, commands, and processing results.
- [ ] 2.2 Provision NATS JetStream streams and subjects required by the rewrite.
- [ ] 2.3 Implement Broadway pipelines that consume JetStream-backed workloads with batching, back-pressure, and retry semantics.
- [ ] 2.4 Build IRC and Discord ingestion agents that publish normalized events into JetStream.

## 3. Processing And Graph Workflows
- [ ] 3.1 Evaluate and implement local ML execution for embeddings and schema-based extraction, using Nx/Bumblebee, GLiNER2, or a deliberate combination of both.
- [ ] 3.2 Implement graph inference and relationship updates against Apache AGE in PostgreSQL.
- [ ] 3.3 Implement Graph-RAG and summarization workflows without Python services in the critical path.

## 4. UI And Operations
- [ ] 4.1 Build Phoenix LiveView interfaces for chat history, dossiers, and graph exploration.
- [ ] 4.2 Implement authenticated web sign-in and tenant-scoped session handling for the Threadr UI.
- [ ] 4.3 Implement self-service API key creation, listing, and revocation for authenticated users.
- [ ] 4.4 Define the first public API surface for tenant-facing automation and control-plane access.
- [ ] 4.5 Define deployment, observability, and operational guidance for the rewrite components.
- [ ] 4.6 Implement or scaffold the Kubernetes control-plane boundary that reconciles tenant bot definitions into bot workloads in the shared namespace.
- [ ] 4.7 Define and persist a controller-owned `ThreadrBot` custom resource contract for bot workloads, with generation-aware status callbacks.
- [ ] 4.8 Verify end-to-end ingestion through JetStream, Broadway consumers, PostgreSQL persistence, and LiveView updates.
