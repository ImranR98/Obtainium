#!/usr/bin/env bash
# Run the build image (matches release.yml's environment: ubuntu 24.04, Temurin
# 21, AGP-managed Android SDK) with the repo mounted. Flutter is provided by the
# repo's pinned .flutter submodule, NOT the image — keeping the Flutter version
# reproducible and consistent with build.sh.
#
#   ./docker/builder.sh                  # interactive shell
#   ./docker/builder.sh ./build.sh       # run a build non-interactively (CI)
#   ./docker/builder.sh flutter build apk --release --flavor normal
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_DIR=$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)
IMAGE=${IMAGE:-flutter-builder-obtainium:latest}
SDK=/opt/android-sdk
JDK=/opt/java/temurin-21

# Flutter comes from the repo's pinned submodule, not the image.
if [ ! -x "${REPO_DIR}/.flutter/bin/flutter" ]; then
    echo "WARNING: .flutter submodule not initialised. Run:" >&2
    echo "  git submodule update --init --recursive" >&2
fi

# Persistent pub/gradle caches so rebuilds are fast (data/ is git-ignored).
mkdir -p "${REPO_DIR}/data/home"

# Allocate a TTY only when attached to one (so CI/piped use works too).
TTY_FLAGS=(-i)
[ -t 0 ] && TTY_FLAGS+=(-t)

# Put the submodule's Flutter first on PATH; JDK + Android SDK tools come from
# the image. JAVA_HOME/ANDROID_HOME carry over from the image's ENV.
exec docker run \
    --rm \
    "${TTY_FLAGS[@]}" \
    --user "$(id -u):$(id -g)" \
    -v "${REPO_DIR}:${REPO_DIR}:z" \
    -v "${REPO_DIR}/data/home:/home/builder:z" \
    -w "${REPO_DIR}" \
    -e HOME=/home/builder \
    -e GRADLE_USER_HOME=/home/builder/.gradle \
    -e ANDROID_USER_HOME=/home/builder/.android \
    -e PATH="${REPO_DIR}/.flutter/bin:/home/builder/.pub-cache/bin:${JDK}/bin:${SDK}/cmdline-tools/latest/bin:${SDK}/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "${IMAGE}" \
    "$@"
