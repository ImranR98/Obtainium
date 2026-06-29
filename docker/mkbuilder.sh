#!/usr/bin/env bash
# Build the toolchain image used by ./docker/builder.sh.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
IMAGE=${IMAGE:-flutter-builder-obtainium}
STAMP=$(date +'%Y%m%d.%H%M%S')

# The Dockerfile COPYs nothing (the source tree is mounted at runtime), so use
# docker/ as the build context. This keeps the context tiny instead of shipping
# the whole repo — including the multi-GB .flutter submodule — to the daemon.
docker build \
    -t "${IMAGE}:latest" \
    -t "${IMAGE}:${STAMP}" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"
