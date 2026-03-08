## 1. Kubernetes-backed developer workflow
- [x] 1.1 Add a Kubernetes-backed local dev mode for Phoenix that connects to cluster-hosted PostgreSQL and NATS instead of the Docker Compose stack.
- [x] 1.2 Keep the Docker Compose path optional, but stop treating it as the default bot-deployment verification workflow.
- [x] 1.3 Document prerequisites and commands for running local `mix phx.server` against Kubernetes-backed dependencies.

## 2. Cluster control-plane exposure
- [x] 2.1 Add Threadr Kubernetes manifests or overlays for exposing the Phoenix control plane at `threadr.carverauto.dev`.
- [x] 2.2 Wire ingress annotations for external-dns and cert-manager TLS using the cluster conventions already used elsewhere in the repository.
- [x] 2.3 Add or document the MetalLB-facing service or ingress contract required for the control-plane endpoint.

## 3. Bot operator wiring
- [x] 3.1 Add a Threadr-owned apply path for the `ThreadrBot` CRD and operator deployment.
- [x] 3.2 Configure the operator to sync against the deployed Threadr control plane with the required machine token and base URL.
- [x] 3.3 Verify that a cluster-backed bot can progress beyond `reconciling` through the operator path.

## 4. Verification and docs
- [x] 4.1 Validate the relevant Kustomize manifests and overlays.
- [x] 4.2 Verify local Phoenix against Kubernetes-hosted dependencies.
- [x] 4.3 Verify the deployed control plane ingress, DNS, and TLS path.
- [x] 4.4 Update README or deployment docs for both local Kubernetes-backed development and cluster deployment.
