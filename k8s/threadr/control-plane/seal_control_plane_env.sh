#!/usr/bin/env bash

set -euo pipefail

input_file="k8s/threadr/control-plane/control-plane-env-secret.example.yaml"
output_file="k8s/threadr/control-plane/control-plane-env.sealedsecret.yaml"
controller_name="sealed-secrets"
controller_namespace="sealed-secrets"
scope="strict"

usage() {
  cat <<'EOF'
Usage: seal_control_plane_env.sh [options]

Options:
  --input <path>                 Plain Secret manifest to seal
  --output <path>                Output SealedSecret manifest path
  --controller-name <name>       Sealed Secrets controller name
  --controller-namespace <ns>    Sealed Secrets controller namespace
  --scope <strict|namespace-wide|cluster-wide>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_file="$2"
      shift 2
      ;;
    --output)
      output_file="$2"
      shift 2
      ;;
    --controller-name)
      controller_name="$2"
      shift 2
      ;;
    --controller-namespace)
      controller_namespace="$2"
      shift 2
      ;;
    --scope)
      scope="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal is required" >&2
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo "input file not found: $input_file" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_file")"

kubeseal \
  --controller-name "$controller_name" \
  --controller-namespace "$controller_namespace" \
  --scope "$scope" \
  --format yaml \
  < "$input_file" \
  > "$output_file"

echo "wrote $output_file"
