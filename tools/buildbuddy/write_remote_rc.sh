#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RC_FILE="${REPO_ROOT}/.bazelrc.remote"
KEY="${BUILDBUDDY_API_KEY:-${BUILDBUDDY_ORG_API_KEY:-}}"

if [[ -z "${KEY}" ]]; then
  echo "Set BUILDBUDDY_API_KEY or BUILDBUDDY_ORG_API_KEY before running this script." >&2
  exit 1
fi

old_umask="$(umask)"
umask 077
printf 'common --remote_header=x-buildbuddy-api-key=%s\n' "${KEY}" > "${RC_FILE}"
umask "${old_umask}"

echo "Wrote ${RC_FILE}" >&2
