# Change: Add Threadr Argo CD ApplicationSet Delivery

## Why
Argo CD is installed in the cluster, but Threadr is not currently managed by any live `Application` or `ApplicationSet`, so commits to the repository do not automatically reconcile the Kubernetes environment. The repository already pins production image digests for the control plane and worker overlays on `main`, but without Argo CD ownership those changes stop at Git and never become cluster state.

## What Changes
- Add an Argo CD `ApplicationSet` that manages the Threadr Kubernetes components for the `threadr` namespace.
- Generate automated-sync Argo CD `Application` resources for the production control-plane and worker overlays, plus the namespace-scoped infrastructure they depend on.
- Define sync ordering and destination rules so namespace-scoped dependencies reconcile before Threadr workloads.
- Document the GitOps flow from image-publish workflow digest updates to Argo CD reconciliation.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: `k8s/argocd/`, `k8s/threadr/`, and deployment documentation for cluster delivery
