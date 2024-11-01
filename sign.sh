#!/bin/bash
set -e

# Script to sign unsigned APKs
# Assumptions:
# 1. Your PGP key is already imported on the locally running agent
# 2. An Android SDK is located at $ANDROID_HOME (or ~/Android/Sdk as fallback)

usage() {
  echo "sign.sh <PATH_TO_KEYSTORE> <PATH_TO_BUILD_DIR>"
  exit 1
}

if [ -z "$1" ] || [ -z "$2" ] || [ ! -f "$1" ] || [ ! -d "$2" ]; then
  usage
fi

KEYSTORE_LOCATION="$1"
BUILD_DIR="$2"

read -s -p "Enter your keystore password: " KEYSTORE_PASSWORD

if [ -z "$ANDROID_HOME" ]; then
  ANDROID_HOME=~/Android/Sdk
fi
if [ ! -d "$ANDROID_HOME" ]; then
  echo "Could not find Android SDK!" >&2
  exit 1
fi

for apk in "$BUILD_DIR"/*-release*.apk; do
  unsignedApk=${apk/-release/-unsigned}
  mv "$apk" "$unsignedApk"
  ${ANDROID_HOME}/build-tools/$(ls ${ANDROID_HOME}/build-tools/ | tail -1)/apksigner sign --ks "$KEYSTORE_LOCATION" --ks-pass pass:"${KEYSTORE_PASSWORD}" --out "${apk}" "${unsignedApk}"
  sha256sum ${apk} | cut -d " " -f 1 >"$apk".sha256
  gpg --batch --sign --detach-sig "$apk".sha256
  rm "$unsignedApk"
done
