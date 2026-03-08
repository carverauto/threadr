## 1. Specification
- [x] 1.1 Confirm which Threadr components in the `threadr` namespace Argo CD must own in the first pass.
- [x] 1.2 Confirm whether Threadr should keep using the default Argo CD project or get a dedicated `AppProject`.

## 2. GitOps Manifests
- [x] 2.1 Add an Argo CD `ApplicationSet` manifest for the supported Threadr components.
- [x] 2.2 Add any required sync-wave annotations or template parameters so dependencies reconcile before workloads.
- [x] 2.3 Remove or supersede the standalone Threadr control-plane `Application` manifest if it becomes redundant.

## 3. Verification
- [x] 3.1 Validate the generated Applications target the intended Kustomize paths.
- [x] 3.2 Verify automated sync settings include prune, self-heal, and namespace creation.
- [x] 3.3 Apply the ApplicationSet in-cluster and confirm Argo CD creates the expected Threadr Applications.
- [x] 3.4 Confirm a commit that updates the production digest pins would result in Argo CD detecting drift for the affected Application.
