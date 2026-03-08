## Context
The Elixir control-plane service has accumulated a large analysis-oriented slice:
- semantic search and QA
- bot and user QA orchestration
- graph answer and topic summarization
- history list and compare
- dossier describe and compare
- generation runtime option resolution for extraction

Those flows already share request structs and provider-option helper modules, but they still depend on private helpers inside `Threadr.ControlPlane.Service`.

## Goals
- Isolate the analysis-facing service behavior into one module with a coherent private helper set.
- Keep all current callers stable by leaving delegating entry points in `Threadr.ControlPlane.Service`.
- Avoid changing product behavior or request/response shapes.

## Non-Goals
- Renaming public service APIs.
- Changing QA/history/dossier routing behavior.
- Reworking authorization or tenant lookup rules.
- Converting callers away from `Threadr.ControlPlane.Service` in this change.

## Proposed Design
- Add a dedicated module, likely `Threadr.ControlPlane.Analysis`, that owns:
  - tenant semantic search
  - user and bot QA answer flows
  - QA compare flows
  - graph answer and topic summary flows
  - history list and compare flows
  - dossier describe and compare flows
  - tenant generation runtime option lookup used by extraction
- Move the private helper functions required by those flows into the new module:
  - semantic/runtime ash option shaping
  - tenant generation runtime resolution
  - embedding catch-up
  - comparison prompt helpers and related option normalization used only by the moved slice
- Leave `Threadr.ControlPlane.Service` with thin delegating functions so no callers need to change during the refactor.

## Risks
- The extracted functions currently rely on several private `Service` helpers for tenant access normalization and system/actor Ash option shaping. Moving the wrong subset can either duplicate too much code or create a circular dependency.
- `Threadr.TenantData.Extraction` depends on `Service.generation_runtime_opts_for_tenant_subject/2`, so the delegation path must remain intact.

## Mitigations
- Move the analysis slice as one coherent block rather than piecemeal.
- Keep the new module internal to the control-plane boundary and retain `Service` delegates for all existing entry points.
- Use the current focused QA/history/dossier test suites plus full `mix precommit` as regression coverage.
