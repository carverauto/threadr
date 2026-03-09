# threadr-2-rewrite Specification

## Purpose
TBD - created by archiving change add-k8s-backed-dev-and-ingress. Update Purpose after archive.
## Requirements
### Requirement: Phoenix local development can target Kubernetes-hosted dependencies
Threadr 2.0 SHALL provide a supported developer workflow for running the local Phoenix control plane against Kubernetes-hosted PostgreSQL and NATS dependencies.

#### Scenario: A maintainer runs local Phoenix against the cluster
- **WHEN** a maintainer starts the supported Kubernetes-backed developer workflow
- **THEN** the local Phoenix server connects to cluster-hosted PostgreSQL and NATS instead of the Docker Compose stack
- **AND** the workflow documents any required port-forwards, environment variables, or authentication steps
- **AND** bot deployment verification does not depend on improving the Docker Compose environment

### Requirement: The Phoenix control plane has a concrete cluster exposure contract
Threadr 2.0 SHALL provide a concrete Kubernetes exposure path for the Phoenix control plane at the intended public hostname.

#### Scenario: Operators deploy the control plane with public ingress
- **WHEN** operators deploy the Threadr control plane into Kubernetes
- **THEN** the repository defines the hostname `threadr.carverauto.dev`
- **AND** ingress wiring includes cert-manager TLS integration
- **AND** DNS automation can be handled through external-dns annotations
- **AND** any required MetalLB-facing service or ingress behavior is documented or defined in the manifests

### Requirement: Cluster-backed bot deployment includes the operator bridge
Threadr 2.0 SHALL provide a Threadr-owned deployment path for the `ThreadrBot` CRD and operator so cluster-backed bot definitions can realize into workloads.

#### Scenario: A cluster-backed bot is created through the control plane
- **WHEN** a tenant creates or updates a bot while using the Kubernetes-backed control plane path
- **THEN** the cluster has the `ThreadrBot` CRD available
- **AND** the operator syncs desired contracts from the control plane
- **AND** the bot can progress beyond `reconciling` through controller status updates

### Requirement: Internal analysis callers use the dedicated control-plane analysis boundary
Threadr 2.0 SHALL route internal analysis-oriented callers through the dedicated control-plane analysis module instead of the broader operational service façade when no operational behavior is needed.

#### Scenario: Web and LiveView analysis flows invoke tenant retrieval
- **WHEN** API controllers or LiveViews perform tenant QA, history comparison, dossier lookup, or dossier comparison
- **THEN** those callers invoke the dedicated control-plane analysis module directly
- **AND** request shapes and user-visible behavior remain unchanged

#### Scenario: Internal bot QA and extraction flows need analysis runtime behavior
- **WHEN** bot QA or extraction runtime lookup needs tenant analysis behavior
- **THEN** those internal callers invoke the dedicated control-plane analysis module directly
- **AND** `Threadr.ControlPlane.Service` remains available as a compatibility façade for callers that still depend on it

### Requirement: Analysis-oriented control-plane retrieval is isolated from operational service flows
Threadr 2.0 SHALL keep analyst-facing retrieval workflows in a dedicated control-plane analysis module instead of mixing them directly into the operational provisioning service implementation.

#### Scenario: Maintainers change tenant QA or history flows
- **WHEN** maintainers update tenant QA, history comparison, dossier comparison, or related analysis retrieval behavior
- **THEN** the implementation for those workflows lives in a dedicated analysis-focused control-plane module
- **AND** `Threadr.ControlPlane.Service` remains a façade entry point for existing callers instead of owning the full implementation directly

#### Scenario: Existing callers use the control-plane service boundary
- **WHEN** web controllers, LiveViews, ingestion runtimes, or extraction flows call the current control-plane service APIs
- **THEN** those callers continue to use the existing `Threadr.ControlPlane.Service` function surface
- **AND** the extracted analysis module preserves the same runtime behavior behind that façade

### Requirement: The control-plane service boundary excludes analysis retrieval APIs
Threadr 2.0 SHALL keep analysis retrieval APIs on the dedicated control-plane analysis module instead of exposing them through the operational control-plane service boundary.

#### Scenario: Maintainers add or update tenant QA and history flows
- **WHEN** maintainers add or modify tenant QA, history comparison, dossier comparison, graph answer, summarization, or extraction runtime retrieval behavior
- **THEN** those public APIs live on `Threadr.ControlPlane.Analysis`
- **AND** `Threadr.ControlPlane.Service` does not re-expose that analysis API surface as delegates

#### Scenario: Operational service callers use the control-plane boundary
- **WHEN** callers use `Threadr.ControlPlane.Service`
- **THEN** that module remains focused on operational control-plane behavior such as tenant, membership, bot, and configuration workflows
- **AND** analysis retrieval behavior remains available through the dedicated analysis boundary

### Requirement: Bot and UI QA resolve actor-focused questions through actor-centric retrieval
Threadr 2.0 SHALL resolve actor-focused bot and UI questions through an actor-centric retrieval path before falling back to generic GraphRAG or semantic QA.

#### Scenario: Bot user asks what a known actor talks about
- **WHEN** a user asks a deployed bot what a known tenant actor mostly talks about
- **THEN** Threadr resolves the referenced handle to a tenant actor record
- **AND** retrieves grounded evidence from that actor's tenant history
- **AND** returns an actor-specific answer instead of only reporting missing generic context

#### Scenario: UI user asks what one actor says about another actor
- **WHEN** a tenant user asks the web QA interface what actor A says about actor B
- **THEN** Threadr resolves the referenced actor handles in the tenant scope
- **AND** retrieves grounded actor-specific evidence before generic semantic fallback
- **AND** returns an answer with the same actor-centric grounding behavior used for bot QA

### Requirement: Actor-centric QA distinguishes missing actors from sparse evidence
Threadr 2.0 SHALL distinguish between actor resolution failure and insufficient evidence when answering actor-focused questions.

#### Scenario: Referenced actor is not present in tenant history
- **WHEN** a user asks about an actor handle that does not resolve to a tenant actor
- **THEN** Threadr replies that the actor is not present in the available tenant history
- **AND** Threadr does not imply that evidence was found but insufficient

#### Scenario: Referenced actor exists but evidence is too sparse
- **WHEN** a user asks about an actor who exists in tenant history but has too little grounded evidence for a safe summary
- **THEN** Threadr replies that the actor does not have enough grounded history for a reliable answer
- **AND** Threadr does not fabricate a topical summary

### Requirement: Tenant QA retrieval maintains embedding coverage for retained message history
Threadr 2.0 SHALL maintain embedding coverage for retained tenant message history used by QA retrieval.

#### Scenario: Tenant history grows through normal ingestion
- **WHEN** new tenant messages are retained for QA
- **THEN** Threadr produces embeddings for those retained messages or schedules bounded catch-up processing
- **AND** actor-centric and semantic retrieval paths can query current tenant history without relying on partial manual backfill

#### Scenario: Operators inspect QA readiness after backlog or restart
- **WHEN** operators inspect a tenant after ingest backlog, restart, or recovery
- **THEN** Threadr exposes whether retained tenant message history is fully embedded or still catching up
- **AND** QA failure states can distinguish missing embeddings from missing actor evidence

