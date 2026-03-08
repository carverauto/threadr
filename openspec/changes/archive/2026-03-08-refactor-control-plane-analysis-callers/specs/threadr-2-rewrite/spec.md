## ADDED Requirements
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
