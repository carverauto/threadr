# Change: Refactor control-plane analysis callers

## Why
The analysis implementation is now isolated in `Threadr.ControlPlane.Analysis`, but the main internal callers still route through `Threadr.ControlPlane.Service`. That leaves the façade wider than necessary and keeps internal analysis traffic coupled to the compatibility boundary.

Routing internal QA, history, dossier, bot QA, and extraction-runtime callers directly to the analysis module will make the boundary clearer and reduce pressure to keep `Service` involved in analysis-only changes.

## What Changes
- Move internal web, LiveView, bot QA, and extraction-runtime callers from `Threadr.ControlPlane.Service` to `Threadr.ControlPlane.Analysis`.
- Keep `Threadr.ControlPlane.Service` as a compatibility façade for external or future callers that still need it.
- Preserve all current request objects, runtime behavior, HTTP behavior, and test expectations.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: analysis-facing controllers, LiveViews, bot QA runtime, extraction runtime lookup, and the control-plane analysis/service boundary
