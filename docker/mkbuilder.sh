#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
D=$(date +'%Y%m%d.%H%M%S%3N')

set -e

cd "${SCRIPT_DIR}/.."
# Create the builder image
docker build \
    -t flutter-builder-obtainium \
    -f ./docker/Dockerfile \
    --build-arg="DEV_UID=$(id -u)" \
    .
