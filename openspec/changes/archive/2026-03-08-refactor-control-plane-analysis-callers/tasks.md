## 1. Caller Migration
- [x] 1.1 Move API controller analysis calls from `Threadr.ControlPlane.Service` to `Threadr.ControlPlane.Analysis`.
- [x] 1.2 Move LiveView analysis calls from `Threadr.ControlPlane.Service` to `Threadr.ControlPlane.Analysis`.
- [x] 1.3 Move bot QA and extraction runtime lookup callers to `Threadr.ControlPlane.Analysis`.

## 2. Boundary Preservation
- [x] 2.1 Keep `Threadr.ControlPlane.Service` delegations intact so the compatibility façade still works.
- [x] 2.2 Preserve request structs, runtime option behavior, and all current response shapes.

## 3. Verification
- [x] 3.1 Verify the focused controller/live QA, history, dossier, bot QA, and extraction suites pass after the caller migration.
- [x] 3.2 Verify `mix precommit` passes after the internal caller migration.
