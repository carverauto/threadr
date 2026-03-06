# ircbot-operator

## Description

### Controller

The operator now contains two controller paths:

- `IRCBot`, the legacy IRC-specific sample controller
- `ThreadrBot`, the Threadr 2.0 control-plane contract controller

`ThreadrBot` is the important one for the rewrite. It watches `cache.threadr.ai/v1alpha1` `ThreadrBot` resources and reconciles the rendered bot workload into a Kubernetes `Deployment`, then writes observed workload state back to the CR status.

The Elixir control plane persists the same `ThreadrBot` document shape in Postgres and exposes it through machine-authenticated endpoints. This operator now includes a sync loop that can consume that feed and upsert the corresponding `ThreadrBot` resources into Kubernetes, and the `ThreadrBot` reconciler can report observed workload status back to the control plane callback endpoint.

Resources labeled as syncer-managed are treated as mirrors of the control-plane contract feed. If a synced `ThreadrBot` disappears from that feed, the sync loop deletes the orphaned CR. Manually-created `ThreadrBot` resources are left alone.

For delete flow, the controller reports terminal `deleted` status back to Phoenix once the workload is gone. The control plane removes the bot record, and the next sync pass removes the now-orphaned `ThreadrBot` CR cleanly.

To enable that bridge, set:

- `THREADR_CONTROL_PLANE_BASE_URL`
- `THREADR_CONTROL_PLANE_TOKEN`
- `THREADR_CONTROL_PLANE_SYNC_INTERVAL` such as `15s`

If those variables are unset, the operator still reconciles manually-applied `ThreadrBot` resources, but it will not pull contracts from the Threadr control plane.

### Local Smoke Flow

Use the Phoenix app to provision a real control-plane contract first:

```sh
cd /Users/mfreeman/src/threadr/elixir/threadr
THREADR_DB_HOST=localhost \
THREADR_DB_PORT=55432 \
THREADR_DB_USER=postgres \
THREADR_DB_PASSWORD=postgres \
THREADR_DB_NAME=threadr_dev \
THREADR_NATS_HOST=localhost \
THREADR_NATS_PORT=54222 \
mix threadr.smoke.bot_contract --tenant-subject threadr-smoke --bot-name irc-main
```

Then run the operator smoke binary against the live Phoenix control plane:

```sh
cd /Users/mfreeman/src/threadr/k8s/operators/ircbot-operator
THREADR_CONTROL_PLANE_BASE_URL=http://127.0.0.1:4000 \
THREADR_CONTROL_PLANE_TOKEN=threadr-smoke-token \
THREADR_BOT_SMOKE_NAMESPACE=threadr \
THREADR_BOT_SMOKE_DEPLOYMENT_NAME=<deployment-name-from-mix-task> \
go run ./cmd/threadrbot-smoke
```

That boots `envtest`, pulls the control-plane contract feed, creates the `ThreadrBot` CR, and waits until the matching Kubernetes `Deployment` exists.



## Getting Started

### Prerequisites
- go version v1.20.0+
- docker version 17.03+.
- kubectl version v1.11.3+.
- Access to a Kubernetes v1.11.3+ cluster.

### To Deploy on the cluster
**Build and push your image to the location specified by `IMG`:**

```sh
make docker-build docker-push IMG=<some-registry>/ircbot-operator:tag
```

**NOTE:** This image ought to be published in the personal registry you specified. 
And it is required to have access to pull the image from the working environment. 
Make sure you have the proper permission to the registry if the above commands don’t work.

**Install the CRDs into the cluster:**

```sh
make install
```

**Deploy the Manager to the cluster with the image specified by `IMG`:**

```sh
make deploy IMG=<some-registry>/ircbot-operator:tag
```

> **NOTE**: If you encounter RBAC errors, you may need to grant yourself cluster-admin 
privileges or be logged in as admin.

**Create instances of your solution**
You can apply the samples (examples) from the config/sample:

```sh
kubectl apply -k config/samples/
```

>**NOTE**: Ensure that the samples has default values to test it out.

### To Uninstall
**Delete the instances (CRs) from the cluster:**

```sh
kubectl delete -k config/samples/
```

**Delete the APIs(CRDs) from the cluster:**

```sh
make uninstall
```

**UnDeploy the controller from the cluster:**

```sh
make undeploy
```

## Contributing
// TODO(user): Add detailed information on how you would like others to contribute to this project

**NOTE:** Run `make help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## License

Copyright 2024.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
