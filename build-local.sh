#!/usr/bin/env bash
set -euo pipefail

# Local build script that mirrors .github/workflows/dockerhub-ubuntu.yml:
#   1. rewrites Dockerfile.base FROM to ubuntu:<release>
#   2. builds the base image
#   3. rewrites Dockerfile FROM to <org>/github-runner-base:ubuntu-<release>
#   4. builds the runner image
#   5. optionally pushes both to Docker Hub

UBUNTU_RELEASE="${UBUNTU_RELEASE:-jammy}"
ORG="${ORG:-phi-labs-ltd}"
STAGE="${STAGE:-all}"
PUSH="${PUSH:-false}"
PLATFORM="${PLATFORM:-}"

usage() {
  cat <<EOF
Usage: $0 [options]

Builds the Ubuntu runner image locally, mirroring the CI workflow.

Options:
  -r, --release RELEASE    Ubuntu release codename (default: ${UBUNTU_RELEASE})
  -o, --org ORG            Docker Hub namespace (default: ${ORG})
  -s, --stage STAGE        What to build: base | runner | all (default: ${STAGE})
  -p, --platform PLATFORM  Target platform, e.g. linux/amd64 (default: host arch)
      --push               Push images to Docker Hub after building
  -h, --help               Show this help

Env overrides: UBUNTU_RELEASE, ORG, STAGE, PUSH, PLATFORM

Examples:
  $0                                         # build base + runner for host arch, no push
  $0 --push                                  # build and push
  $0 -s runner                               # only rebuild runner (base must already exist)
  $0 -r noble --org acme --push              # 24.04 base, custom org, push
  PLATFORM=linux/amd64,linux/arm64 $0 --push # multi-arch (requires --push)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--release)  UBUNTU_RELEASE="$2"; shift 2 ;;
    -o|--org)      ORG="$2"; shift 2 ;;
    -s|--stage)    STAGE="$2"; shift 2 ;;
    -p|--platform) PLATFORM="$2"; shift 2 ;;
    --push)        PUSH=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  case "$(uname -m)" in
    x86_64)          PLATFORM=linux/amd64 ;;
    aarch64|arm64)   PLATFORM=linux/arm64 ;;
    *)               PLATFORM="linux/$(uname -m)" ;;
  esac
fi

case "$STAGE" in
  base|runner|all) ;;
  *) echo "Invalid --stage: $STAGE (expected: base | runner | all)" >&2; exit 1 ;;
esac

if [[ "$PLATFORM" == *,* && "$PUSH" != "true" ]]; then
  echo "Multi-platform builds require --push (buildx cannot --load multi-arch images)." >&2
  exit 1
fi

cd "$(dirname "$0")"

BASE_TAG="${ORG}/github-runner-base:ubuntu-${UBUNTU_RELEASE}"
BASE_LATEST="${ORG}/github-runner-base:latest"
RUNNER_TAG="${ORG}/github-runner:ubuntu-${UBUNTU_RELEASE}"
RUNNER_LATEST="${ORG}/github-runner:latest"

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx is required but not available." >&2
  exit 1
fi

output_flag=(--load)
[[ "$PUSH" == "true" ]] && output_flag=(--push)

build_base() {
  echo ">>> Building base image: $BASE_TAG"
  local tmp
  tmp=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  sed "s|^FROM.*|FROM ubuntu:${UBUNTU_RELEASE}|" Dockerfile.base > "$tmp"

  docker buildx build \
    --file "$tmp" \
    --platform "$PLATFORM" \
    --tag "$BASE_TAG" \
    --tag "$BASE_LATEST" \
    --pull \
    "${output_flag[@]}" \
    .
}

build_runner() {
  echo ">>> Building runner image: $RUNNER_TAG"
  local tmp
  tmp=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  sed "s|^FROM.*|FROM ${BASE_TAG}|" Dockerfile > "$tmp"

  docker buildx build \
    --file "$tmp" \
    --platform "$PLATFORM" \
    --tag "$RUNNER_TAG" \
    --tag "$RUNNER_LATEST" \
    --pull \
    "${output_flag[@]}" \
    .
}

case "$STAGE" in
  base)   build_base ;;
  runner) build_runner ;;
  all)    build_base; build_runner ;;
esac

echo
echo "Done."
if [[ "$PUSH" == "true" ]]; then
  echo "Pushed:"
  [[ "$STAGE" != "runner" ]] && echo "  $BASE_TAG"
  [[ "$STAGE" != "runner" ]] && echo "  $BASE_LATEST"
  [[ "$STAGE" != "base" ]]   && echo "  $RUNNER_TAG"
  [[ "$STAGE" != "base" ]]   && echo "  $RUNNER_LATEST"
else
  echo "Loaded locally (docker images | grep ${ORG}):"
  [[ "$STAGE" != "runner" ]] && echo "  $BASE_TAG"
  [[ "$STAGE" != "base" ]]   && echo "  $RUNNER_TAG"
fi
