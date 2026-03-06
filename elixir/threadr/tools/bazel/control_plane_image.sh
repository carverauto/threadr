#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  echo "BUILD_WORKSPACE_DIRECTORY is not set; run this via 'bazel run'" >&2
  exit 1
fi

readonly action="${1:-}"
shift || true

if [[ "${action}" != "build" && "${action}" != "push" ]]; then
  echo "usage: bazel run //elixir/threadr:control_plane_image_{build,push} -- [--image IMAGE] [--tag TAG] [--platform PLATFORM]" >&2
  exit 1
fi

image="ghcr.io/carverauto/threadr/threadr-control-plane"
build_platform=""
push_platforms="${THREADR_IMAGE_PUSH_PLATFORMS:-linux/amd64,linux/arm64}"
declare -a tags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      image="$2"
      shift 2
      ;;
    --tag)
      tags+=("$2")
      shift 2
      ;;
    --platform)
      build_platform="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ${#tags[@]} -eq 0 ]]; then
  tags=("main")
fi

context_dir="${BUILD_WORKSPACE_DIRECTORY}/elixir/threadr"
dockerfile="${context_dir}/Dockerfile"

if [[ ! -f "${dockerfile}" ]]; then
  echo "missing Dockerfile at ${dockerfile}" >&2
  exit 1
fi

cmd=(docker buildx build -f "${dockerfile}")

for tag in "${tags[@]}"; do
  cmd+=(-t "${image}:${tag}")
done

if [[ "${action}" == "push" ]]; then
  cmd+=(--platform "${build_platform:-${push_platforms}}" --push)
else
  if [[ -n "${build_platform}" ]]; then
    cmd+=(--platform "${build_platform}")
  fi

  cmd+=(--load)
fi

cmd+=("${context_dir}")

echo "running: ${cmd[*]}" >&2
"${cmd[@]}"
