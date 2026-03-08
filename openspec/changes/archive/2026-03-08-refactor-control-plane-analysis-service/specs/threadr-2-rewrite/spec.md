## ADDED Requirements
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
