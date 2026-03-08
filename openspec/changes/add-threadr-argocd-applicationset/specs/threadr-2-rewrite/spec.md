## ADDED Requirements
### Requirement: Threadr production components can be reconciled by Argo CD from Git
Threadr 2.0 SHALL provide an Argo CD-managed GitOps delivery path for the supported Kubernetes components in the `threadr` namespace.

#### Scenario: Argo CD creates Threadr applications from the repository
- **WHEN** operators apply the supported Threadr Argo CD configuration in the `argocd` namespace
- **THEN** Argo CD creates or manages the expected Threadr applications from this repository
- **AND** each generated application targets the intended Kustomize path for its component
- **AND** the destination namespace is `threadr`

#### Scenario: Production digest pin updates reconcile automatically
- **WHEN** the repository updates a production image digest pin for a Threadr component on the tracked Git revision
- **THEN** Argo CD detects drift for the affected Threadr application
- **AND** automated sync can reconcile the cluster to the new pinned image state without manual `kubectl apply`

### Requirement: Threadr GitOps delivery preserves dependency ordering and ownership boundaries
Threadr 2.0 SHALL define dependency ordering and ownership boundaries for Argo CD delivery so namespace-scoped services reconcile predictably.

#### Scenario: Dependency components reconcile before workloads
- **WHEN** Argo CD syncs the supported Threadr applications
- **THEN** namespace-scoped dependencies such as the database or messaging layer can reconcile before dependent Threadr workloads
- **AND** workload applications do not require operators to apply the same manifests manually beforehand

#### Scenario: Tenant bot workloads remain outside ApplicationSet ownership
- **WHEN** operators inspect the Argo CD-managed Threadr applications
- **THEN** the ApplicationSet scope is explicit about which namespace-scoped components it owns
- **AND** operator-managed tenant bot Deployments are not accidentally treated as Argo CD-owned resources unless explicitly added in a future change
