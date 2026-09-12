#!/usr/bin/env bash
# Generates the tiny signed APKs used by the integration tests.
#
# The APKs are manifest-only (no code), carry a known versionCode/versionName,
# and are never committed: they live under build/e2e_assets/.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"

if [ ! -d "$SDK/build-tools" ]; then
  echo "Android SDK build-tools not found under $SDK" >&2
  exit 1
fi
BUILD_TOOLS="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"

if [ ! -d "$SDK/platforms" ]; then
  echo "Android SDK platforms not found under $SDK" >&2
  exit 1
fi
PLATFORM_JAR="$SDK/platforms/$(ls "$SDK/platforms" | grep -E '^android-[0-9]+$' | sort -V | tail -1)/android.jar"

AAPT2="$BUILD_TOOLS/aapt2"
ALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"
KEYSTORE="$HOME/.android/debug.keystore"
PKG="com.obtainium.e2etest"
OUT_DIR="${1:-$REPO_DIR/build/e2e_assets}"

if [ ! -f "$KEYSTORE" ]; then
  echo "Creating a debug keystore at $KEYSTORE"
  keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for v in 1 2; do
  cat > "$work/AndroidManifest-$v.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PKG"
    android:versionCode="$v"
    android:versionName="$v">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36" />
    <application android:label="E2E Test App" android:hasCode="false" />
</manifest>
EOF
  "$AAPT2" link -o "$work/unsigned-$v.apk" \
    --manifest "$work/AndroidManifest-$v.xml" \
    -I "$PLATFORM_JAR"
  "$ALIGN" -f -p 4 "$work/unsigned-$v.apk" "$work/aligned-$v.apk"
  "$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey \
    --out "$OUT_DIR/testapp-v$v.apk" "$work/aligned-$v.apk"
done

"$AAPT2" dump badging "$OUT_DIR/testapp-v2.apk" | head -1
ls -la "$OUT_DIR"
