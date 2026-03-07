# Project Context

## Purpose
Threadr is an open source conversation-ingestion and social-graph platform. It collects messages from chat systems such as IRC and Discord, normalizes them into events, stores message and relationship data in Neo4j, generates embeddings for semantic search, and supports graph-aware question answering and summarization.

The main product goals visible in this repository are:
- infer relationships between actors from public conversations
- build and query a graph of users, channels, messages, and mentions
- support LLM and graph-RAG workflows over historical chat data
- run as a Kubernetes-first system with bots, processors, and supporting services deployed as separate components

## Tech Stack
- Go 1.21 for bots, API services, shared ports/adapters, and the Kubernetes operator
- Python 3 for message processing, embeddings, LangChain workflows, and query tooling
- Neo4j as the primary graph database, including vector indexes for embeddings
- NATS JetStream and CloudEvents for message transport between ingest and processing components
- FastAPI and Uvicorn for Python service endpoints
- Fiber for the Go API server
- Firebase Authentication for user auth and custom claims in the API layer
- OpenAI, LangChain, LangGraph, and sentence-transformers for LLM, embeddings, and retrieval workflows
- Kubernetes with Kustomize manifests under `k8s/`
- Skaffold for local build/deploy loops
- Terraform for GCP/GKE and state-bucket infrastructure
- `ko` for building the IRC and Discord bot images
- Argo CD, Linkerd, MetalLB, Calico, cert-manager, cloudflared, and other cluster add-ons are tracked in-repo as deployment manifests

## Project Conventions

### Code Style
Follow the language-native conventions already present in the repo:
- Go code should stay `gofmt`-formatted, use exported `CamelCase` names, keep package names lowercase, and prefer small packages under `pkg/` with binaries under `cmd/`
- Python code uses module-oriented organization under `python/`, `snake_case` functions, and uppercase environment variable names in settings modules
- Configuration is primarily YAML, Terraform HCL, and `.env`-style environment variables
- Prefer extending existing packages and modules instead of creating parallel abstractions
- Treat `python/attic/` and other attic/lab content as experimental or historical unless a change explicitly targets it

### Architecture Patterns
The repository leans toward a ports-and-adapters layout in Go:
- `pkg/ports/` defines interfaces for brokers, graph storage, and message handlers
- `pkg/adapters/` contains concrete implementations for NATS, Neo4j, IRC, Discord, and CloudEvents plumbing
- `cmd/` contains thin entrypoints for deployable binaries

System flow is event-driven:
1. Bots ingest chat messages from IRC or Discord.
2. Messages are published to NATS JetStream as CloudEvents-like payloads.
3. Python processors consume those events, extract relationships and commands, write to Neo4j, and publish embedding work.
4. Query tooling and LLM workflows read from Neo4j vector indexes and graph data.

The repo is also infrastructure-heavy and Kubernetes-first:
- most deployable services have manifests under `k8s/`
- `k8s/threadr/base` is the main application kustomization
- cluster add-ons and experiments live alongside application manifests
- an IRCBot Kubernetes operator exists under `k8s/operators/ircbot-operator`

### Testing Strategy
Testing is uneven across the repo, so specs should reflect the current state honestly:
- Go service code appears to rely mostly on manual verification and runtime testing
- the IRCBot operator has the clearest automated test path, using Ginkgo/Gomega plus controller-runtime `envtest`
- Python test coverage is minimal at the moment; `python/message_processing/tests/test_consumer.py` exists but is currently empty
- for changes in core ingest or processing flows, prefer adding focused tests where practical and at minimum verify the impacted entrypoint locally
- for Kubernetes changes, validate manifests and deployment wiring in the relevant kustomization or operator workflow before considering work complete

### Git Workflow
The repository history shows lightweight, pragmatic commits rather than a rigid formal workflow. Conventions that fit the current project:
- keep commits small and scoped to one logical change
- use descriptive commit messages; existing history includes short operational commits and merge commits
- expect work to happen on feature or update branches and land through merges, but do not assume strict conventional-commit enforcement
- avoid mixing application logic, infrastructure churn, and experiments in one commit when possible

## Domain Context
Threadr is centered on relationship inference from chat data. Important domain concepts include:
- actors or users across platforms such as IRC and Discord
- messages, channels, mentions, and temporal ordering of conversations
- inferred relationships such as direct mentions and other interaction signals
- graph storage of users, channels, and messages in Neo4j
- embeddings and vector search for semantic retrieval over message history
- graph-RAG style queries such as "Does Alice know Bob?" or "What does this user talk about?"

This repo mixes two overlapping use cases:
- threat-actor or community relationship analysis from public chat systems
- organizational communication analysis, summarization, and information retrieval across internal chat platforms

## Important Constraints
- This is a polyglot monorepo, so changes often need to respect both Go and Python runtimes
- Message ingestion and downstream processing are loosely coupled through NATS subjects and streams; changing payload shape can break multiple components
- Neo4j schema and vector-index assumptions matter for both ingestion and query paths
- Many services depend on environment-provided secrets and credentials such as `NATSURL`, `NKEYSEED`, `NEO4J_*`, `OPENAI_API_KEY`, and Firebase credentials
- Kubernetes deployment is a first-class concern; infrastructure changes should account for kustomize overlays, cluster networking, and operator resources
- There is significant experimental material in `python/attic/`, `python/lab/`, and some `k8s/` folders; avoid treating those as production paths unless the change explicitly targets them
- The repository includes home-lab and cloud infrastructure artifacts, so not every manifest should be assumed portable or production-hardened

## External Dependencies
- Neo4j for graph storage and vector search
- NATS JetStream for messaging and async processing
- OpenAI APIs for embeddings and LLM-powered workflows
- LangChain and LangGraph as orchestration libraries in Python query and processing paths
- Firebase Authentication and Google APIs for API-layer identity and claims management
- Discord and IRC networks as message sources
- Google Cloud Platform, especially GKE, GCS, and KMS, for infrastructure managed through Terraform
- Kubernetes ecosystem components in `k8s/`, including Argo CD, Linkerd, MetalLB, Calico, cert-manager, cloudflared, JupyterHub, Ollama, vLLM, and Nebula Graph
