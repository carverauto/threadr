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
