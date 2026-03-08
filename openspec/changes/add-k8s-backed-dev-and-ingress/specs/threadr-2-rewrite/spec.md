## ADDED Requirements

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
