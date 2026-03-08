## 1. Boundary Reduction
- [x] 1.1 Remove the analysis-oriented public delegate functions from `Threadr.ControlPlane.Service`.
- [x] 1.2 Update any remaining callers and tests to use `Threadr.ControlPlane.Analysis` directly.

## 2. Behavior Preservation
- [x] 2.1 Preserve tenant QA, bot QA, history, dossier, graph answer, summary, and extraction runtime behavior.
- [x] 2.2 Keep operational control-plane behavior on `Threadr.ControlPlane.Service` unchanged.

## 3. Verification
- [x] 3.1 Verify focused analysis and extraction suites pass after removing the delegates.
- [x] 3.2 Verify `mix precommit` passes after the boundary reduction.
