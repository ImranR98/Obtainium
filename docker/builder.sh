#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd ${SCRIPT_DIR}/..
mkdir -p ./data/home
docker run \
    --rm \
    -ti \
    --net host \
    -v "${PWD}/../:${PWD}/../":z \
    -w "${PWD}" \
    --name flutter-dev-obtainium \
    --user $(id -u) \
    -v ./data/home:/home/${USER}:z \
    -e USER=${USER} \
    -e HOME=/home/${USER} \
    -e ANDROID_USER_HOME=${HOME}/.android \
    -e GRADLE_USER_HOME=${HOME}/.gradle \
    -e PS1="${debian_chroot:+($debian_chroot)}${USER}@\h:\w\$ " \
    flutter-builder-obtainium