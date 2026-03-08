## ADDED Requirements
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
