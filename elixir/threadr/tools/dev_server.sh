#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: tools/dev_server.sh [--seed-demo TENANT_SUBJECT] [--skip-compose] [--skip-setup] [--reset-data]

Starts the local Threadr dev stack against the Docker Compose CNPG + NATS services,
initializes the dev database and JetStream topology, and runs `mix phx.server`.

Options:
  --seed-demo TENANT_SUBJECT  Seed demo chat history into the given tenant before boot.
  --skip-compose             Do not run `docker compose up -d`.
  --skip-setup               Do not run `mix ecto.create`, `mix ecto.migrate`, or `mix threadr.nats.setup`.
  --reset-data               Destroy local Docker volumes before booting the stack.
  --help                     Show this help text.
EOF
}

SEED_DEMO_SUBJECT=""
SKIP_COMPOSE="false"
SKIP_SETUP="false"
RESET_DATA="false"

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
    --skip-compose)
      SKIP_COMPOSE="true"
      shift
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

if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

if [[ -f ".env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env.local"
  set +a
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

if [[ "$SKIP_COMPOSE" != "true" ]]; then
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
fi

if [[ "$SKIP_SETUP" != "true" ]]; then
  mix ecto.create || true
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
  web:    ${THREADR_WEB_ENABLED}
  worker: messaging=${THREADR_MESSAGING_ENABLED} broadway=${THREADR_BROADWAY_ENABLED}
EOF

exec mix phx.server
