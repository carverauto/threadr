#!/usr/bin/env bash

set -euo pipefail

image="ghcr.io/carverauto/threadr/threadr-control-plane"
tag=""
file="k8s/threadr/overlays/control-plane/production/image-patch.yaml"
digest=""

usage() {
  cat <<'EOF'
Usage: update_production_digest.sh --tag <tag> [options]

Options:
  --image <image>    OCI image name to resolve
  --tag <tag>        image tag to inspect
  --file <path>      image patch file to update
  --digest <digest>  explicit digest override for testing
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      image="$2"
      shift 2
      ;;
    --tag)
      tag="$2"
      shift 2
      ;;
    --file)
      file="$2"
      shift 2
      ;;
    --digest)
      digest="$2"
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

if [[ -z "$tag" && -z "$digest" ]]; then
  echo "--tag is required unless --digest is provided" >&2
  exit 1
fi

if [[ -z "$digest" ]]; then
  digest="$(docker buildx imagetools inspect "${image}:${tag}" --format '{{json .Manifest.Digest}}' | tr -d '"')"
fi

if [[ ! "$digest" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
  echo "resolved digest is invalid: $digest" >&2
  exit 1
fi

IMAGE="$image" DIGEST="$digest" FILE_PATH="$file" perl -0pi -e '
  my $image = $ENV{IMAGE};
  my $digest = $ENV{DIGEST};
  my $replacement = "${image}\@${digest}";
  s/\Q$image\E\@sha256:[A-Za-z0-9._-]+/$replacement/g;
' "$file"

echo "updated $file to $image@$digest"
