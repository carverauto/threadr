## ADDED Requirements

### Requirement: BEAM-native rewrite architecture
Threadr 2.0 SHALL consolidate ingestion, asynchronous processing, APIs, and real-time user interfaces into an Elixir-based system running on the BEAM, with Python removed from the primary runtime path.

#### Scenario: Rewrite scope is defined
- **WHEN** maintainers plan or implement first-class Threadr 2.0 services
- **THEN** those services are built in Elixir
- **AND** Python is not required for ingestion, message processing, embeddings, graph inference, or the user-facing application path

### Requirement: Ash is the primary application framework
Threadr 2.0 SHALL use Ash and AshPostgres as the primary framework for application resources, actions, and persistence rules.

#### Scenario: A core rewrite resource is defined
- **WHEN** maintainers add or modify first-class Threadr 2.0 domain models
- **THEN** those models are expressed as Ash resources and domains
- **AND** Phoenix and LiveView integrate with those resources instead of bypassing them with ad hoc persistence layers

### Requirement: Durable messaging remains on NATS JetStream
Threadr 2.0 SHALL continue to use NATS JetStream as the durable transport for normalized chat events and downstream asynchronous workloads.

#### Scenario: Ingestion publishes durable events
- **WHEN** an IRC or Discord agent normalizes an incoming message or command
- **THEN** it publishes that event to a NATS JetStream stream and subject
- **AND** the rewrite architecture does not replace JetStream with Phoenix PubSub alone

#### Scenario: Tenant-owned events are scoped in the subject hierarchy
- **WHEN** the system publishes tenant-owned chat or processing events to NATS
- **THEN** it scopes those events under a tenant-specific subject token
- **AND** that token uses NATS-compatible characters
- **AND** the system does not rely on raw database identifiers as the primary operational subject namespace

### Requirement: Message consumers use Broadway
Threadr 2.0 SHALL process JetStream-backed workloads through Broadway consumers.

#### Scenario: Downstream processing consumes messages
- **WHEN** the system handles asynchronous workloads such as embeddings, graph inference, summarization, or command execution
- **THEN** those workloads are consumed through Broadway pipelines backed by JetStream
- **AND** the consumer topology can apply batching, concurrency limits, acknowledgements, and back-pressure

### Requirement: PostgreSQL replaces Neo4j for graph and retrieval workloads
Threadr 2.0 SHALL replace Neo4j with PostgreSQL using Apache AGE, pgvector, TimescaleDB, and ParadeDB.

#### Scenario: Rewrite services persist graph and retrieval data
- **WHEN** rewrite components store graph relationships, embeddings, temporal message data, or search indexes
- **THEN** they write to PostgreSQL with the required extensions
- **AND** Neo4j is not the primary datastore for Threadr 2.0

### Requirement: Tenant data is isolated with schema-based multitenancy
Threadr 2.0 SHALL isolate tenant-owned data with schema-based multitenancy on a shared PostgreSQL cluster.

#### Scenario: A new tenant is created
- **WHEN** a tenant is provisioned in the rewrite system
- **THEN** the system creates or assigns a dedicated PostgreSQL schema for that tenant
- **AND** tenant-owned actors, channels, messages, relationships, and embeddings are stored in that tenant schema
- **AND** the architecture does not require a dedicated PostgreSQL instance per tenant

### Requirement: Public control-plane resources remain cross-tenant
Threadr 2.0 SHALL keep cross-tenant control-plane resources in a shared public schema.

#### Scenario: The system manages tenant and bot lifecycle records
- **WHEN** the application stores tenant definitions or bot deployment definitions
- **THEN** those records live in shared control-plane data structures that can be read by the platform control plane
- **AND** those records remain separate from tenant-scoped conversation and graph data

### Requirement: Control-plane images are built and published through Bazel entrypoints
Threadr 2.0 SHALL use Bazel entrypoints as the canonical interface for building and publishing control-plane OCI images.

#### Scenario: A maintainer builds a local control-plane image
- **WHEN** a maintainer needs a local control-plane release image
- **THEN** the repository provides a Bazel target that assembles that image from a Bazel-built Phoenix release artifact
- **AND** the maintainer does not need a separate handwritten shell recipe outside the repository

#### Scenario: CI publishes the control-plane image
- **WHEN** CI publishes the control-plane image to GHCR
- **THEN** the workflow runs Bazel build and test steps in `opt` mode using the configured remote execution and cache backend
- **AND** the workflow invokes the Bazel push entrypoint
- **AND** the remote Bazel profile resolves Linux amd64 OCI helper binaries rather than reusing macOS host-tool binaries on the remote executor
- **AND** the published image is the same artifact shape the Kubernetes deployment overlays expect
- **AND** the workflow does not duplicate the image build logic in an ad hoc `docker build` step

#### Scenario: CI refreshes the production image pin after publish
- **WHEN** CI successfully publishes a new control-plane image for the default branch
- **THEN** the workflow resolves the pushed GHCR digest
- **AND** the production deployment overlay is updated to reference that immutable digest

### Requirement: Production deployment overlays define the control-plane runtime contract
Threadr 2.0 SHALL provide an environment-oriented deployment overlay that pins the control-plane hostname, TLS Secret name, bootstrap operator email, and immutable image reference while leaving production secret material out of Git.

#### Scenario: Operators prepare a production control-plane deployment
- **WHEN** operators apply the production deployment overlay through ArgoCD or Kustomize
- **THEN** the overlay defines the intended external hostname, TLS Secret name, and published control-plane image reference
- **AND** the overlay documents the required runtime Secret names the cluster must provide
- **AND** the repository provides a Sealed Secrets workflow for materializing `threadr-control-plane-env` without committing plaintext production secrets

### Requirement: Tenants can provision bots through a control plane
Threadr 2.0 SHALL provide a control plane that allows tenants to create and manage Threadr bot workloads.

#### Scenario: A tenant creates a bot
- **WHEN** a tenant submits a bot definition for a supported platform
- **THEN** the control plane records the desired bot state
- **AND** the system can reconcile that desired state into Kubernetes workloads inside the shared namespace

### Requirement: Bot lifecycle transitions are enforced by Ash state machines
Threadr 2.0 SHALL model operational bot lifecycle transitions with Ash state machines instead of ad hoc status writes.

#### Scenario: An application workflow requests reconciliation
- **WHEN** a tenant creates or updates a bot definition
- **THEN** the bot lifecycle state transitions through an explicit Ash action into `reconciling`
- **AND** callers do not mutate operational status with direct attribute writes

#### Scenario: Observed workload status is reported
- **WHEN** a controller callback or workload observer reports bot progress
- **THEN** the system applies that change through an explicit Ash state transition action
- **AND** the system rejects transitions that are not valid from the bot's current lifecycle state

### Requirement: The control plane emits a controller-owned desired-state contract
Threadr 2.0 SHALL emit a durable desired-state contract for each tenant bot workload that a Kubernetes controller can own.

#### Scenario: A bot reconcile operation is dispatched
- **WHEN** the control plane processes a bot apply or delete intent
- **THEN** it persists a concrete desired-state document for that bot workload
- **AND** that document is shaped as a concrete Kubernetes custom resource definition the controller understands
- **AND** that document includes bot identity, tenant identity, deployment identity, generation, and the rendered workload specification
- **AND** the document is durable so a controller can read it independently of the original API request

#### Scenario: A cluster-side sync component applies desired contracts
- **WHEN** a cluster-side sync component reads the machine-authenticated desired-state contract feed
- **THEN** it upserts the corresponding `ThreadrBot` custom resources in Kubernetes
- **AND** the Kubernetes controller reconciles those resources without requiring the Phoenix application to write workloads directly

#### Scenario: A controller reports workload status
- **WHEN** a Kubernetes controller reports observed bot status back to the control plane
- **THEN** it includes the desired-state generation it is reporting on
- **AND** the control plane rejects stale reports for older generations
- **AND** accepted reports update the bot's observed lifecycle state and observation metadata

### Requirement: Tenant users can sign in to the web application
Threadr 2.0 SHALL provide authenticated sign-in for tenant users accessing the web UI.

#### Scenario: A tenant user starts an authenticated session
- **WHEN** a valid tenant user completes the supported sign-in flow
- **THEN** the system creates an authenticated web session
- **AND** subsequent UI access can be authorized against that user identity and tenant membership

### Requirement: The first operator administrator is bootstrapped deterministically
Threadr 2.0 SHALL provide a first-install bootstrap path that creates the initial operator administrator exactly once and requires that bootstrap credential to be rotated before normal control-plane use.

#### Scenario: A fresh installation has no operator administrator
- **WHEN** the install-time bootstrap job or task runs against a deployment where no operator-admin user exists
- **THEN** the system creates exactly one operator-admin user in persisted application state
- **AND** the bootstrap path emits a one-time installation credential or setup secret for that user
- **AND** subsequent bootstrap executions do not create additional operator-admin users automatically

#### Scenario: A bootstrap administrator signs in for the first time
- **WHEN** a bootstrap-created operator-admin authenticates with the installation credential
- **THEN** the system requires password rotation before granting normal control-plane access
- **AND** the rotated credential becomes the durable sign-in secret instead of the original bootstrap credential

### Requirement: Threadr exposes a public tenant-facing API
Threadr 2.0 SHALL expose a public API for tenant-facing automation and integrations.

#### Scenario: An authenticated client calls the public API
- **WHEN** a client submits a request to a tenant-facing API endpoint with valid credentials
- **THEN** the system authenticates the caller
- **AND** authorizes the request against that caller's tenant access
- **AND** executes the request without requiring operator-only internal endpoints

### Requirement: Authenticated users can manage their own API keys
Threadr 2.0 SHALL let authenticated users create and revoke API keys for their own account.

#### Scenario: A signed-in user creates an API key
- **WHEN** an authenticated user requests a new API key
- **THEN** the system creates a new credential owned by that user
- **AND** returns the plaintext secret only at creation time
- **AND** stores only non-plaintext credential material for subsequent verification

#### Scenario: A signed-in user revokes an API key
- **WHEN** an authenticated user revokes one of their API keys
- **THEN** the system prevents further public API use with that credential
- **AND** the user can still view non-secret metadata about that key after revocation

### Requirement: Elixir-native orchestration with Elixir-owned ML backends
Threadr 2.0 SHALL keep workflow orchestration in Elixir and SHALL evaluate ML backends based on workload fit using BEAM-native inference paths where appropriate, without reintroducing Python model services into the rewrite.

#### Scenario: The system runs AI-driven processing
- **WHEN** Threadr generates embeddings, performs graph-aware retrieval, or orchestrates autonomous processing flows
- **THEN** those flows execute from Elixir services
- **AND** the implementation may use Nx, Bumblebee, or another BEAM-native local inference path selected for the workload
- **AND** any remote model providers are invoked from Elixir rather than delegated to Python workers

#### Scenario: Structured extraction stays out of Python services
- **WHEN** the team evaluates local models for entity extraction, classification, or relation-oriented extraction
- **THEN** it selects a BEAM-native local inference path or a remote provider invoked from Elixir
- **AND** it does not add Python worker services back into the rewrite to satisfy structured extraction

#### Scenario: Structured extraction persists tenant-scoped entities and facts
- **WHEN** Threadr extracts entities or temporal facts from a chat message
- **THEN** the extraction runs through an Elixir-owned provider boundary
- **AND** the resulting entities and facts are persisted in the tenant schema with message linkage and temporal metadata

### Requirement: Real-time analyst interfaces use Phoenix LiveView
Threadr 2.0 SHALL provide analyst-facing chat monitoring, dossier, and graph exploration interfaces through Phoenix LiveView.

#### Scenario: Users observe incoming data and graph changes
- **WHEN** new messages, relationships, or analysis results are available
- **THEN** the Phoenix application can push those updates into LiveView-driven interfaces in near real time

### Requirement: Graph exploration uses a binary GPU-first rendering pipeline
Threadr 2.0 SHALL implement analyst graph exploration with a versioned binary snapshot contract, `deck.gl` rendering, roaring bitmap overlays, and a Wasm client compute layer instead of a JSON-only graph UI.

#### Scenario: Tenant graph snapshots stream over a versioned binary contract
- **GIVEN** an authenticated tenant user opens the graph exploration surface
- **WHEN** the application emits a graph snapshot revision
- **THEN** the snapshot payload is delivered as a versioned binary contract suitable for Apache Arrow IPC decoding
- **AND** the payload includes explicit metadata required for deterministic client decode
- **AND** the client keeps the last accepted revision active when a newer revision is rejected

#### Scenario: Graph filters apply locally from bitmap metadata
- **GIVEN** a decoded tenant graph snapshot revision and its bitmap metadata are loaded
- **WHEN** the analyst toggles visual classes or neighborhood filters that do not require graph recomputation
- **THEN** the client applies those filters locally using roaring bitmap or equivalent typed-mask data
- **AND** the system does not require a server round-trip for visual-only updates

#### Scenario: Graph rendering uses deck.gl on supported clients
- **GIVEN** the analyst client supports the required GPU capabilities
- **WHEN** the graph exploration surface initializes
- **THEN** the client renders the graph through `deck.gl`
- **AND** the implementation prefers WebGPU-capable execution paths when available

#### Scenario: Wasm handles hot-path graph interactions
- **GIVEN** a loaded graph snapshot with high-cardinality nodes and edges
- **WHEN** the analyst performs repeated traversal, mask, or interpolation interactions
- **THEN** those hot-path operations execute in a Wasm or equivalent typed-memory client layer
- **AND** the implementation avoids object-per-node JavaScript transforms on the interactive path
