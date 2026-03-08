# Change: Add Kubernetes-backed developer workflow and control-plane ingress

## Why
The current local developer flow is centered on Docker Compose, but the active bot and control-plane work is Kubernetes-first. That mismatch makes the local Phoenix server look functional while bot deployment status cannot progress the same way it does in cluster-backed environments.

The repository also has a partial control-plane deployment but not a complete, documented path for exposing the Phoenix LiveView app at a real hostname with DNS, TLS, and load-balancer integration.

## What Changes
- Add a Kubernetes-backed local developer workflow for running `mix phx.server` against cluster-hosted PostgreSQL and NATS instead of the Docker Compose stack.
- Keep Docker Compose as an optional path, but stop treating it as the default developer workflow for bot deployment verification.
- Add a deployable Kubernetes path for the Phoenix control plane, including the control-plane ingress contract for `threadr.carverauto.dev`.
- Define Threadr-specific manifest wiring for ingress annotations, external-dns integration, cert-manager TLS, and MetalLB service exposure.
- Wire the `ThreadrBot` CRD and operator deployment into the Threadr Kubernetes deployment story so bot definitions can progress beyond `reconciling` in cluster-backed environments.
- Document the developer and operator steps required to run local Phoenix against Kubernetes and to deploy the control plane end to end.

## Impact
- Affected specs: `threadr-2-rewrite`
- Affected code: `elixir/threadr/tools/dev_server.sh`, Threadr Kubernetes manifests under `k8s/threadr/`, operator deployment wiring under `k8s/operators/ircbot-operator/`, and deployment/developer documentation
