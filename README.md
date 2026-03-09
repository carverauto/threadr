![threadNexus](https://raw.githubusercontent.com/carverauto/threadnexus/main/assets/thread-banner.png)

# Threadr

Threadr is an Elixir-based conversation intelligence system for tenant-scoped
chat ingestion, reconstruction, QA, and operator-managed bot runtimes.

The current implementation is centered on:

- Phoenix and LiveView for the control plane and analyst UI
- Ash and AshPostgres for public-schema and tenant-schema resources
- NATS JetStream and Broadway for normalized event delivery and ingest
- tenant-scoped chat persistence, relationship inference, and reconstruction
- ML boundaries for embeddings, extraction, semantic QA, graph QA, and
  conversation-grounded QA

This repository is no longer organized around the older Python or
JupyterBook-style implementation ideas. The active product surface lives under
[elixir/threadr](/Users/mfreeman/src/threadr/elixir/threadr).

## What Threadr Does

Threadr ingests public chat activity from platforms such as IRC and Discord,
normalizes it into tenant-scoped events, and persists:

- actors, aliases, and alias observations
- channels, messages, mentions, and relationships
- context events such as edits, deletes, reactions, presence, nick changes,
  joins, parts, quits, and topic changes
- message links, reconstructed conversations, memberships, and pending items
- embeddings, extracted entities, extracted facts, and dialogue acts

On top of that data, Threadr provides:

- analyst-facing QA, history, dossier, and graph surfaces
- actor-centric and conversation-grounded retrieval
- periodic conversation summaries, cluster review, and relationship recompute
- control-plane APIs and LiveViews for tenant and bot management

## Repository Layout

- [elixir/threadr](/Users/mfreeman/src/threadr/elixir/threadr): main Phoenix application, event pipeline, ML boundaries, tests, and operational docs
- [k8s/threadr](/Users/mfreeman/src/threadr/k8s/threadr): control-plane and operator manifests
- [openspec](/Users/mfreeman/src/threadr/openspec): active and archived spec changes
- [cmd](/Users/mfreeman/src/threadr/cmd): supporting bot and operator binaries

## Getting Started

The main app README is here:

- [elixir/threadr/README.md](/Users/mfreeman/src/threadr/elixir/threadr/README.md)

Typical local development starts with:

```bash
cd elixir/threadr
./tools/dev_server.sh
```

If you explicitly want the older local-only compose stack instead of the
default Kubernetes-backed dev flow:

```bash
cd elixir/threadr
./tools/dev_server.sh --use-compose
```

## Verification

Useful entrypoints:

```bash
cd elixir/threadr
mix precommit
THREADR_RUN_INTEGRATION=true mix test test/threadr/messaging/smoke_test.exs
mix threadr.smoke.ingest --tenant-name "Acme Threat Intel" --mentions bob,carol
```

The integration smoke test exercises the JetStream plus Broadway plus
PostgreSQL path end to end. The main app README covers the broader operator,
Discord, and deployment smoke flows.

## Community

Join us on Discord:

- https://discord.gg/YnzMAJvb
