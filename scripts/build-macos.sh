#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
IMAGE="${MACOS_BUILDER_IMAGE:-ghcr.io/chris533/gio-macos-builder:15.5}"

if [[ "${1:-}" == "--project-dir" && -n "${2:-}" ]]; then
  PROJECT_DIR="$(cd "$2" && pwd)"
  shift 2
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "Image ${IMAGE} not cached locally; pulling or building locally..."
  docker pull "${IMAGE}" || docker build -t "${IMAGE}" "${BUILDER_ROOT}"
fi

exec docker run --rm \
  -v "${PROJECT_DIR}:/workspace" \
  -v gio-macos-cache:/cache \
  "${IMAGE}" "$@"
