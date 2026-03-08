## Context
Threadr now has a Phoenix control plane, LiveView bot management, a durable `ThreadrBot` contract, and a Kubernetes operator path. The current developer workflow still defaults to local Docker Compose services, which is adequate for basic application development but not for validating the Kubernetes-backed bot lifecycle or real ingress exposure.

The next useful environment contract is Kubernetes-first:
- local `mix phx.server` can talk to cluster-hosted dependencies
- the cluster can host the Phoenix control plane itself
- the public hostname and TLS path are concrete and repeatable

This design should follow the existing operational style already used in this repository and in `~/src/serviceradar`, especially for ingress annotations, external-dns, cert-manager, and MetalLB.

## Goals
- Support a local Phoenix developer workflow that talks to Kubernetes-hosted Postgres and NATS.
- Provide a concrete Kubernetes deployment path for the Threadr Phoenix control plane.
- Expose the control plane at `threadr.carverauto.dev` with cert-manager-managed TLS and external-dns-managed DNS.
- Ensure cluster-backed bot deployments have the `ThreadrBot` CRD and operator available.
- Keep the contract documented and reproducible in-repo.

## Non-Goals
- Making the Docker Compose stack a better approximation of Kubernetes bot deployment.
- Replacing the current in-cluster control plane with a local-only bot runner.
- Designing a production-grade secret-management system beyond the current Secret or SealedSecret contract.

## Architecture Decisions

### Kubernetes-backed local Phoenix development
The local Phoenix server should gain a Kubernetes-backed mode instead of more Compose behavior. The safest default is a mode that establishes local connectivity to cluster services through `kubectl port-forward` or another explicit local bridge, then runs `mix phx.server` with those forwarded endpoints.

This avoids assuming the developer machine can route directly to cluster service DNS names while still letting the application use the real cluster Postgres and NATS instances.

### Cluster control-plane exposure
The control-plane Kubernetes deployment remains the source of truth for the in-cluster Phoenix app. Threadr-specific manifests should define:
- the `threadr-control-plane` Service and ingress
- ingress annotations for cert-manager and external-dns
- the intended public hostname `threadr.carverauto.dev`
- the TLS Secret name expected by ingress

MetalLB support should be expressed at the service or ingress layer only where the cluster requires it, reusing the same operational style already used in ServiceRadar manifests.

### Bot operator deployment contract
Installing only the `ThreadrBot` CRD is insufficient. A working cluster-backed bot path requires:
- the `ThreadrBot` CRD
- the operator deployment
- operator environment wiring for `THREADR_CONTROL_PLANE_BASE_URL`, `THREADR_CONTROL_PLANE_TOKEN`, and sync interval

Threadr-specific manifests should therefore include an operator overlay or documented apply path that uses the existing operator image and points it at the deployed control plane.

### Documentation contract
The repository should document two distinct workflows clearly:
1. local Phoenix against Kubernetes-hosted dependencies
2. fully deployed in-cluster Phoenix plus operator

Those flows should be explicit about prerequisites, required secrets, DNS controller expectations, TLS issuer names, and validation steps.

## Risks And Mitigations
- Local Kubernetes-backed dev can become brittle if it assumes direct cluster networking.
  Mitigation: use an explicit local bridge such as `kubectl port-forward` and make it script-managed.
- Ingress, DNS, and TLS wiring can become environment-specific quickly.
  Mitigation: keep Threadr manifests focused on Threadr-owned resources and make cluster addon assumptions explicit.
- Operator deployment may drift from the control-plane contract.
  Mitigation: reuse the existing operator image and HTTP sync contract instead of inventing a second integration path.
