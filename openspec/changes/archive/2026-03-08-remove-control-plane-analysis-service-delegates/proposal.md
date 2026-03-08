# Change: Remove control-plane analysis service delegates

## Why
The analysis implementation has already been extracted into `Threadr.ControlPlane.Analysis`, and the internal callers have already been migrated to that module. The remaining analysis-related functions on `Threadr.ControlPlane.Service` are now compatibility delegates only.

Keeping those delegates indefinitely leaves the public boundary ambiguous and invites new analysis code to keep attaching to `Service` even though the real implementation lives elsewhere.

## What Changes
- Remove the analysis-oriented delegate functions from `Threadr.ControlPlane.Service`.
- Treat `Threadr.ControlPlane.Analysis` as the primary boundary for tenant QA, history, dossier, graph answer, summarization, and tenant generation-runtime retrieval flows.
- Update any remaining tests or callers that still invoke the removed `Service` delegate surface.
- Preserve operational `Service` behavior and preserve analysis runtime behavior behind the new boundary.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: `elixir/threadr/lib/threadr/control_plane/service.ex`, `elixir/threadr/lib/threadr/control_plane/analysis.ex`, remaining analysis-facing tests or callers
