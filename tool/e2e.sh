#!/usr/bin/env bash
# Runs the emulator end-to-end suites locally.
#
# Usage: tool/e2e.sh [--phone|--tv] [--no-install]
#
# With no arguments it detects whether the attached device is a TV or a phone
# and runs every suite that applies, including the install/update suite.
#
# Requires:
#   - a running emulator or device (launching it is left to the user)
#   - E2E_DEVICE to choose a device when more than one is attached
#
# You should never need to invoke `flutter test integration_test/...` by hand;
# this script performs the per-suite setup (test APKs, local server, installer
# attribution, animation scales) that the suites rely on.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
ADB="${ADB:-$SDK/platform-tools/adb}"
if [ -x "$REPO_DIR/.flutter/bin/flutter" ]; then
  FLUTTER="$REPO_DIR/.flutter/bin/flutter"
else
  FLUTTER="flutter"
fi

TARGET="auto"
WITH_INSTALL=true
PORT="${E2E_PORT:-8000}"
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --phone|phone) TARGET="phone" ;;
    --tv|tv) TARGET="tv" ;;
    --no-install) WITH_INSTALL=false ;;
    # Kept for backwards compatibility; install tests are on by default.
    --install|--with-install) WITH_INSTALL=true ;;
    *)
      echo "Unknown argument: $arg (expected --phone, --tv or --no-install)" >&2
      exit 1
      ;;
  esac
done
# Environment overrides let CI or one-off runs force the install suite either way.
if [ "${E2E_RUN_INSTALL:-}" = "true" ] || [ "${E2E_RUN_INSTALL:-}" = "1" ]; then
  WITH_INSTALL=true
elif [ "${E2E_RUN_INSTALL:-}" = "false" ] || [ "${E2E_RUN_INSTALL:-}" = "0" ]; then
  WITH_INSTALL=false
fi

if ! "$ADB" get-state >/dev/null 2>&1 && [ -z "${E2E_DEVICE:-}" ]; then
  echo "No device attached. Start the desired emulator first." >&2
  exit 1
fi
if [ -n "${E2E_DEVICE:-}" ]; then
  DEV="$E2E_DEVICE"
else
  mapfile -t DEVICES < <("$ADB" devices | awk '$2 == "device" {print $1}')
  if [ "${#DEVICES[@]}" -ne 1 ]; then
    echo "Expected exactly one device; set E2E_DEVICE (found: ${DEVICES[*]:-none})" >&2
    exit 1
  fi
  DEV="${DEVICES[0]}"
fi

IS_TV=false
if "$ADB" -s "$DEV" shell pm list features 2>/dev/null | grep -q leanback; then
  IS_TV=true
fi
if [ "$TARGET" = "auto" ]; then
  if [ "$IS_TV" = true ]; then TARGET="tv"; else TARGET="phone"; fi
fi
if [ "$TARGET" = "tv" ] && [ "$IS_TV" = false ]; then
  echo "$DEV is not an Android TV device (omit --tv or use --phone)" >&2
  exit 1
fi
if [ "$TARGET" = "phone" ] && [ "$IS_TV" = true ]; then
  echo "$DEV is an Android TV device (omit --phone or use --tv)" >&2
  exit 1
fi

PHONE_SUITES=(
  smoke_test.dart
  add_remove_app_test.dart
  html_links_test.dart
  app_list_density_test.dart
  codeberg_auth_test.dart
  screens_navigation_test.dart
)
TV_SUITES=(
  tv_navigation_test.dart
  tv_controls_test.dart
  tv_layout_test.dart
)
INSTALL_SUITES=(
  install_update_test.dart
  install_as_downloaded_test.dart
  signing_cert_test.dart
)
if [ "$TARGET" = "phone" ] && $WITH_INSTALL; then
  PHONE_SUITES+=("${INSTALL_SUITES[@]}")
fi

echo "Device:  $DEV ($TARGET)"
echo "Suites:  ${PHONE_SUITES[*]}"
if [ "$TARGET" = "tv" ]; then
  echo "         ${TV_SUITES[*]}"
fi
echo "Install/update tests: $WITH_INSTALL (disable with --no-install)"
echo

# Generate the tiny APKs the add/remove and install suites download.
E2E_PUBLIC_BASE_URL="http://10.0.2.2:$PORT" "$SCRIPT_DIR/e2e_assets.sh" >/dev/null

# Serve them over HTTP for the emulator (10.0.2.2 maps to the host loopback).
# The custom server adds delayed /slow/ paths used by the install-ordering
# suite (#2611) and is threaded so parallel downloads really overlap.
python3 "$SCRIPT_DIR/e2e_server.py" "$PORT" "$REPO_DIR/build/e2e_assets" >/dev/null 2>&1 &
SERVER_PID=$!

# Animation scales make focus and route transitions flaky; store originals.
ORIG_WINDOW=$("$ADB" -s "$DEV" shell settings get global window_animation_scale 2>/dev/null | tr -d '\r')
ORIG_TRANSITION=$("$ADB" -s "$DEV" shell settings get global transition_animation_scale 2>/dev/null | tr -d '\r')
ORIG_ANIMATOR=$("$ADB" -s "$DEV" shell settings get global animator_duration_scale 2>/dev/null | tr -d '\r')
restore_device_state() {
  kill "$SERVER_PID" 2>/dev/null || true
  "$ADB" -s "$DEV" shell settings put global window_animation_scale "${ORIG_WINDOW:-1.0}" >/dev/null 2>&1 || true
  "$ADB" -s "$DEV" shell settings put global transition_animation_scale "${ORIG_TRANSITION:-1.0}" >/dev/null 2>&1 || true
  "$ADB" -s "$DEV" shell settings put global animator_duration_scale "${ORIG_ANIMATOR:-1.0}" >/dev/null 2>&1 || true
  "$ADB" -s "$DEV" uninstall com.obtainium.e2etest >/dev/null 2>&1 || true
  "$ADB" -s "$DEV" uninstall com.obtainium.e2etest2 >/dev/null 2>&1 || true
}
trap restore_device_state EXIT

"$ADB" -s "$DEV" shell settings put global window_animation_scale 0.0
"$ADB" -s "$DEV" shell settings put global transition_animation_scale 0.0
"$ADB" -s "$DEV" shell settings put global animator_duration_scale 0.0

# Resets and reinstalls the fixture packages at v1 with Obtainium as their
# installer, so the stock installer can update them without a user prompt.
# Called before every install suite because earlier suites leave newer
# versions installed (and an interrupted run may leave a downgrade blocker).
reset_install_targets() {
  for pkg in com.obtainium.e2etest com.obtainium.e2etest2; do
    "$ADB" -s "$DEV" uninstall "$pkg" >/dev/null 2>&1 || true
  done
  for apk in testapp-v1.apk testapp2-v1.apk; do
    if ! "$ADB" -s "$DEV" install -r -i dev.imranr.obtainium.debug \
      "$REPO_DIR/build/e2e_assets/$apk" >/dev/null; then
      echo "Failed to pre-install $apk with Obtainium as installer" >&2
      exit 1
    fi
  done
}

if [ "$TARGET" = "phone" ] && $WITH_INSTALL; then
  reset_install_targets
fi

run_suite() {
  local suite="$1"
  echo "=== $suite ==="
  if [ "$TARGET" = "phone" ] && $WITH_INSTALL && \
    [[ " ${INSTALL_SUITES[*]} " == *" $suite "* ]]; then
    reset_install_targets
  fi
  # Bound each suite so a hung test cannot block the run indefinitely.
  timeout 600 "$FLUTTER" test "integration_test/$suite" \
    -d "$DEV" --flavor normal --no-uninstall \
    --dart-define=E2E_BASE_URL="http://10.0.2.2:$PORT" \
    --dart-define=E2E_RUN_INSTALL="$WITH_INSTALL"
}

if [ "$TARGET" = "phone" ]; then
  for suite in "${PHONE_SUITES[@]}"; do
    run_suite "$suite"
  done
else
  for suite in "${TV_SUITES[@]}"; do
    run_suite "$suite"
  done
fi

echo "E2E suites finished for $DEV"
