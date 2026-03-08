# Change: Refactor control-plane analysis service boundary

## Why
`Threadr.ControlPlane.Service` now mixes two different responsibilities: operational control-plane workflows such as tenant and bot lifecycle management, and analyst-facing retrieval workflows such as QA, history comparison, and dossier comparison. The analysis-related code has grown into a coherent subsystem with its own request types, provider-option helpers, and orchestration path, but it still lives inside the large operational service module.

That makes the module harder to navigate, raises the cost of future changes, and keeps compile/runtime dependencies for analysis logic attached to unrelated provisioning behavior.

## What Changes
- Extract the analyst-facing QA, history, dossier, and tenant generation-runtime retrieval flows from `Threadr.ControlPlane.Service` into a dedicated analysis-focused control-plane module.
- Keep `Threadr.ControlPlane.Service` as the existing public compatibility entry point by delegating the moved functions to the new module.
- Move the private helpers required by those flows with the extracted implementation so analysis-specific request shaping, tenant lookup, embedding catch-up, and comparison prompting live together.
- Preserve existing request types, caller shapes, HTTP/LiveView behavior, and test expectations.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: `elixir/threadr/lib/threadr/control_plane/service.ex`, a new analysis-focused control-plane module, QA/history/dossier service tests, and any helper code needed by the extracted analysis flows
