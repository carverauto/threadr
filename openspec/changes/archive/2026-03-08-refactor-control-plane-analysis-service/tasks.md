## 1. Module Split
- [x] 1.1 Create a dedicated control-plane analysis module for tenant QA, history, dossier, and generation-runtime retrieval flows.
- [x] 1.2 Move the supporting private helpers required by those flows out of `Threadr.ControlPlane.Service` and into the new module.
- [x] 1.3 Keep `Threadr.ControlPlane.Service` as a façade by delegating the moved public functions to the new module.

## 2. Behavior Preservation
- [x] 2.1 Preserve the existing request structs, runtime option behavior, and caller-facing function signatures.
- [x] 2.2 Preserve bot QA, user QA, history compare, dossier compare, and extraction runtime behavior without changing HTTP or LiveView callers.

## 3. Verification
- [x] 3.1 Verify the focused control-plane QA/history/dossier suites still pass after the split.
- [x] 3.2 Verify `mix precommit` passes with the extracted module boundary.
