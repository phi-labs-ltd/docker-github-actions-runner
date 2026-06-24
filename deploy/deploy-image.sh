#!/usr/bin/env bash
set -euo pipefail

# Ships the runner image from this host to a remote host over SSH,
# compressing the stream to speed up the transfer (docker save | gzip |
# ssh 'gunzip | docker load'). No registry, no intermediate tarball.

IMAGE="${IMAGE:-phi-labs-ltd/github-runner:ubuntu-noble}"
DEST="${DEST:-junaid@10.0.1.4}"
KEY="${KEY:-$HOME/.ssh/bolt-deploy.key}"

usage() {
  cat <<EOF
Usage: $0 [options]

Streams a local Docker image to a remote host over SSH (gzip-compressed).

Options:
  -i, --image IMAGE    Image to transfer (default: ${IMAGE})
  -d, --dest  DEST     Remote SSH target, user@host (default: ${DEST})
  -k, --key   KEY      SSH private key (default: ${KEY})
  -h, --help           Show this help

Env overrides: IMAGE, DEST, KEY

Examples:
  $0                                         # defaults
  $0 -i phi-labs-ltd/github-runner:ubuntu-jammy
  $0 -d junaid@10.0.1.7 -k ~/.ssh/other.key
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image) IMAGE="$2"; shift 2 ;;
    -d|--dest)  DEST="$2";  shift 2 ;;
    -k|--key)   KEY="$2";   shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image not found locally: $IMAGE" >&2
  echo "Build it first (e.g. ./build-local.sh -r noble)." >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "SSH key not found: $KEY" >&2
  exit 1
fi

echo ">>> Shipping $IMAGE -> $DEST"
docker save "$IMAGE" \
  | gzip \
  | ssh -i "$KEY" "$DEST" 'gunzip | docker load'

echo
echo "Done. Verify on the remote with: docker images | grep github-runner"
