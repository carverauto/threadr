#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ENV_LOCAL_FILE="$ROOT_DIR/.env.local"

env_file_sets_var() {
  local file_path="$1"
  local variable_name="$2"

  if [[ ! -f "$file_path" ]]; then
    return 1
  fi

  rg -q "^[[:space:]]*${variable_name}=" "$file_path"
}

usage() {
  cat <<'EOF'
Usage: tools/dev_server.sh [--seed-demo TENANT_SUBJECT] [--use-compose] [--skip-setup] [--reset-data]

Starts the local Threadr dev server. By default it runs Phoenix locally against
Kubernetes-hosted CNPG + NATS dependencies via managed `kubectl port-forward`
sessions. `--use-compose` switches back to the Docker Compose dev stack.

Options:
  --seed-demo TENANT_SUBJECT  Seed demo chat history into the given tenant before boot.
  --use-compose              Use the Docker Compose CNPG + NATS stack instead of Kubernetes.
  --namespace NAME           Kubernetes namespace for the Threadr services. Default: `threadr`.
  --db-service NAME          Kubernetes Postgres service name. Default: `cnpg-rw`.
  --db-secret NAME           Kubernetes Secret with DB creds. Default: `cnpg-app`.
  --db-local-port PORT       Local port for the Postgres port-forward. Default: `55432`.
  --nats-service NAME        Kubernetes NATS service name. Default: `nats`.
  --nats-local-port PORT     Local port for the NATS port-forward. Default: `54222`.
  --skip-setup               Do not run `mix ecto.create`, `mix ecto.migrate`, or `mix threadr.nats.setup`.
  --reset-data               Destroy local Docker volumes before booting the stack.
  --help                     Show this help text.
EOF
}

SEED_DEMO_SUBJECT=""
USE_COMPOSE="false"
SKIP_SETUP="false"
RESET_DATA="false"
K8S_NAMESPACE="threadr"
K8S_DB_SERVICE="cnpg-rw"
K8S_DB_SECRET="cnpg-app"
K8S_DB_LOCAL_PORT="55432"
K8S_NATS_SERVICE="nats"
K8S_NATS_LOCAL_PORT="54222"

PORT_FORWARD_PIDS=()
PORT_FORWARD_LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed-demo)
      if [[ $# -lt 2 ]]; then
        echo "--seed-demo requires a tenant subject" >&2
        exit 1
      fi

      SEED_DEMO_SUBJECT="$2"
      shift 2
      ;;
    --use-compose)
      USE_COMPOSE="true"
      shift
      ;;
    --namespace)
      K8S_NAMESPACE="$2"
      shift 2
      ;;
    --db-service)
      K8S_DB_SERVICE="$2"
      shift 2
      ;;
    --db-secret)
      K8S_DB_SECRET="$2"
      shift 2
      ;;
    --db-local-port)
      K8S_DB_LOCAL_PORT="$2"
      shift 2
      ;;
    --nats-service)
      K8S_NATS_SERVICE="$2"
      shift 2
      ;;
    --nats-local-port)
      K8S_NATS_LOCAL_PORT="$2"
      shift 2
      ;;
    --skip-setup)
      SKIP_SETUP="true"
      shift
      ;;
    --reset-data)
      RESET_DATA="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

THREADR_DB_USER_WAS_SET="${THREADR_DB_USER+1}"
THREADR_DB_PASSWORD_WAS_SET="${THREADR_DB_PASSWORD+1}"
THREADR_DB_NAME_WAS_SET="${THREADR_DB_NAME+1}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
fi

if [[ -f "$ENV_LOCAL_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_LOCAL_FILE"
  set +a
fi

if [[ -z "$THREADR_DB_USER_WAS_SET" ]] && env_file_sets_var "$ENV_LOCAL_FILE" "THREADR_DB_USER"; then
  THREADR_DB_USER_WAS_SET="1"
fi

if [[ -z "$THREADR_DB_PASSWORD_WAS_SET" ]] && env_file_sets_var "$ENV_LOCAL_FILE" "THREADR_DB_PASSWORD"; then
  THREADR_DB_PASSWORD_WAS_SET="1"
fi

if [[ -z "$THREADR_DB_NAME_WAS_SET" ]] && env_file_sets_var "$ENV_LOCAL_FILE" "THREADR_DB_NAME"; then
  THREADR_DB_NAME_WAS_SET="1"
fi

export THREADR_DB_HOST="${THREADR_DB_HOST:-localhost}"
export THREADR_DB_PORT="${THREADR_DB_PORT:-55432}"
export THREADR_DB_USER="${THREADR_DB_USER:-postgres}"
export THREADR_DB_PASSWORD="${THREADR_DB_PASSWORD:-postgres}"
export THREADR_DB_NAME="${THREADR_DB_NAME:-threadr_dev}"
export THREADR_TEST_DB_NAME="${THREADR_TEST_DB_NAME:-threadr_test}"
export THREADR_NATS_HOST="${THREADR_NATS_HOST:-localhost}"
export THREADR_NATS_PORT="${THREADR_NATS_PORT:-54222}"
export THREADR_WEB_ENABLED="${THREADR_WEB_ENABLED:-true}"
export THREADR_MESSAGING_ENABLED="${THREADR_MESSAGING_ENABLED:-false}"
export THREADR_BROADWAY_ENABLED="${THREADR_BROADWAY_ENABLED:-false}"
export PHX_SERVER=true

SERVER_THREADR_MESSAGING_ENABLED="$THREADR_MESSAGING_ENABLED"
SERVER_THREADR_BROADWAY_ENABLED="$THREADR_BROADWAY_ENABLED"

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

wait_for_health() {
  local container_name="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-2}"
  local attempt=1

  while [[ $attempt -le $attempts ]]; do
    local status
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_name" 2>/dev/null || true)"

    if [[ "$status" == "exited" ]]; then
      echo "${container_name} exited during startup. Recent logs:" >&2
      docker logs --tail=80 "$container_name" >&2 || true
      return 1
    fi

    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      return 0
    fi

    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done

  echo "Timed out waiting for ${container_name} to become healthy" >&2
  return 1
}

wait_for_local_port() {
  local host="$1"
  local port="$2"
  local attempts="${3:-50}"
  local sleep_seconds="${4:-0.2}"
  local attempt=1

  while [[ $attempt -le $attempts ]]; do
    if nc -z "$host" "$port" >/dev/null 2>&1; then
      return 0
    fi

    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done

  return 1
}

port_is_available() {
  local host="$1"
  local port="$2"

  ! nc -z "$host" "$port" >/dev/null 2>&1
}

pick_local_port() {
  local requested_port="$1"
  local port="$requested_port"
  local attempts=50

  while [[ $attempts -gt 0 ]]; do
    if port_is_available 127.0.0.1 "$port"; then
      echo "$port"
      return 0
    fi

    port=$((port + 1))
    attempts=$((attempts - 1))
  done

  echo "Unable to find a free local port starting at ${requested_port}" >&2
  exit 1
}

cleanup_port_forwards() {
  for pid in "${PORT_FORWARD_PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done

  if [[ -n "$PORT_FORWARD_LOG_DIR" && -d "$PORT_FORWARD_LOG_DIR" ]]; then
    rm -rf "$PORT_FORWARD_LOG_DIR"
  fi
}

start_port_forward() {
  local name="$1"
  local namespace="$2"
  local resource="$3"
  local mapping="$4"
  local host_port="${mapping%%:*}"
  local log_file="$PORT_FORWARD_LOG_DIR/${name}.log"

  if ! command -v nc >/dev/null 2>&1; then
    echo "Missing required command: nc" >&2
    exit 1
  fi

  kubectl -n "$namespace" port-forward "$resource" "$mapping" >"$log_file" 2>&1 &
  local pid=$!
  PORT_FORWARD_PIDS+=("$pid")

  if ! wait_for_local_port 127.0.0.1 "$host_port"; then
    echo "Timed out waiting for port-forward ${name} on ${mapping}" >&2
    cat "$log_file" >&2 || true
    exit 1
  fi
}

read_secret_key() {
  local namespace="$1"
  local secret_name="$2"
  local key="$3"

  kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data.${key}}" | base64 -d
}

configure_k8s_dev() {
  require_command kubectl
  require_command base64
  require_command nc

  PORT_FORWARD_LOG_DIR="$(mktemp -d)"
  trap cleanup_port_forwards EXIT

  local selected_db_port
  local selected_nats_port
  selected_db_port="$(pick_local_port "$K8S_DB_LOCAL_PORT")"
  selected_nats_port="$(pick_local_port "$K8S_NATS_LOCAL_PORT")"

  if [[ "$selected_db_port" != "$K8S_DB_LOCAL_PORT" ]]; then
    echo "Local port ${K8S_DB_LOCAL_PORT} is busy; using ${selected_db_port} for Kubernetes Postgres" >&2
  fi

  if [[ "$selected_nats_port" != "$K8S_NATS_LOCAL_PORT" ]]; then
    echo "Local port ${K8S_NATS_LOCAL_PORT} is busy; using ${selected_nats_port} for Kubernetes NATS" >&2
  fi

  K8S_DB_LOCAL_PORT="$selected_db_port"
  K8S_NATS_LOCAL_PORT="$selected_nats_port"

  if [[ -z "$THREADR_DB_USER_WAS_SET" ]]; then
    export THREADR_DB_USER="$(read_secret_key "$K8S_NAMESPACE" "$K8S_DB_SECRET" username)"
  fi

  if [[ -z "$THREADR_DB_PASSWORD_WAS_SET" ]]; then
    export THREADR_DB_PASSWORD="$(read_secret_key "$K8S_NAMESPACE" "$K8S_DB_SECRET" password)"
  fi

  if [[ -z "$THREADR_DB_NAME_WAS_SET" ]]; then
    export THREADR_DB_NAME="$(read_secret_key "$K8S_NAMESPACE" "$K8S_DB_SECRET" dbname)"
  fi

  export THREADR_DB_HOST="127.0.0.1"
  export THREADR_DB_PORT="$K8S_DB_LOCAL_PORT"
  export THREADR_NATS_HOST="127.0.0.1"
  export THREADR_NATS_PORT="$K8S_NATS_LOCAL_PORT"
  export THREADR_DB_SSL="${THREADR_DB_SSL:-true}"
  export THREADR_DB_SSL_VERIFY="${THREADR_DB_SSL_VERIFY:-verify_none}"

  start_port_forward db "$K8S_NAMESPACE" "svc/${K8S_DB_SERVICE}" "${K8S_DB_LOCAL_PORT}:5432"
  start_port_forward nats "$K8S_NAMESPACE" "svc/${K8S_NATS_SERVICE}" "${K8S_NATS_LOCAL_PORT}:4222"
}

if [[ "$USE_COMPOSE" == "true" ]]; then
  if [[ "$RESET_DATA" == "true" ]]; then
    docker compose down -v
  fi

  docker compose up -d
  if ! wait_for_health "threadr-cnpg"; then
    cat >&2 <<'EOF'

Local CNPG failed to start. If you recently upgraded the local Postgres image
from 16 to 18, your old Docker volume is incompatible.

Reset local data with:
  tools/dev_server.sh --reset-data

Or manually:
  docker compose down -v
  docker compose up -d
EOF
    exit 1
  fi

  wait_for_health "threadr-nats"
else
  configure_k8s_dev
fi

if [[ "$SKIP_SETUP" != "true" ]]; then
  if [[ "$USE_COMPOSE" == "true" ]]; then
    mix ecto.create || true
  fi

  mix ecto.migrate
  mix threadr.tenants.migrate --all
  THREADR_MESSAGING_ENABLED=true THREADR_BROADWAY_ENABLED=false mix threadr.nats.setup

  if [[ -n "$SEED_DEMO_SUBJECT" ]]; then
    mix threadr.seed.demo --tenant-subject "$SEED_DEMO_SUBJECT"
  fi
fi

export THREADR_MESSAGING_ENABLED="$SERVER_THREADR_MESSAGING_ENABLED"
export THREADR_BROADWAY_ENABLED="$SERVER_THREADR_BROADWAY_ENABLED"

cat <<EOF
Threadr dev environment:
  app:    http://localhost:${PORT:-4000}
  db:     postgres://${THREADR_DB_USER}@${THREADR_DB_HOST}:${THREADR_DB_PORT}/${THREADR_DB_NAME}
  nats:   nats://${THREADR_NATS_HOST}:${THREADR_NATS_PORT}
  mode:   $(if [[ "$USE_COMPOSE" == "true" ]]; then echo "compose"; else echo "kubernetes"; fi)
  web:    ${THREADR_WEB_ENABLED}
  worker: messaging=${THREADR_MESSAGING_ENABLED} broadway=${THREADR_BROADWAY_ENABLED}
EOF

exec mix phx.server
