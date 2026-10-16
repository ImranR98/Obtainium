#!/usr/bin/env bash
# Read-only toolchain snapshot for the dependency-updates skill.
#
# Usage: scripts/toolchain-report.sh
#
# Prints the repo's current Android/Flutter toolchain values next to the ones
# the installed Flutter SDK uses for new projects. Makes no changes.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../../.." &>/dev/null && pwd)"
FLUTTER_SDK="$REPO_ROOT/.flutter"
GRADLE_UTILS="$FLUTTER_SDK/packages/flutter_tools/lib/src/android/gradle_utils.dart"
VERSION_JSON="$FLUTTER_SDK/bin/cache/flutter.version.json"

extract() { # file regex [sed-expr]
    local file="$1" regex="$2" sed_expr="${3:-}"
    [ -f "$file" ] || return 0
    if [ -n "$sed_expr" ]; then
        grep -oE "$regex" "$file" 2>/dev/null | head -1 | sed -E "$sed_expr" || true
    else
        grep -oE "$regex" "$file" 2>/dev/null | head -1 || true
    fi
}

if [ -f "$VERSION_JSON" ]; then
    flutter_version="$(extract "$VERSION_JSON" '"frameworkVersion": *"[^"]+"' 's/.*"frameworkVersion": *"([^"]+)"/\1/')"
    flutter_revision="$(extract "$VERSION_JSON" '"frameworkRevision": *"[^"]+"' 's/.*"frameworkRevision": *"([^"]+)"/\1/')"
    dart_version="$(extract "$VERSION_JSON" '"dartSdkVersion": *"[^"]+"' 's/.*"dartSdkVersion": *"([^"]+)"/\1/')"
else
    flutter_version="(submodule not initialised)"
    flutter_revision=""
    dart_version=""
fi

repo_gradle="$(extract "$REPO_ROOT/android/gradle/wrapper/gradle-wrapper.properties" 'gradle-[0-9][0-9.]*-all' 's/gradle-//;s/-all//')"
repo_agp="$(grep 'com.android.application' "$REPO_ROOT/android/settings.gradle.kts" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)"
repo_kotlin="$(grep 'org.jetbrains.kotlin.android' "$REPO_ROOT/android/settings.gradle.kts" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)"
repo_compile="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'release\([0-9]+\)' 's/release\(([0-9]+)\)/\1/')"
repo_compile_minor="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'minorApiLevel = [0-9]+' 's/minorApiLevel = //')"
[ -z "$repo_compile" ] && repo_compile="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'compileSdk = [^ ]+' 's/compileSdk = //')"
repo_minsdk="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'minSdk = [0-9]+' 's/minSdk = //')"
repo_targetsdk="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'targetSdk = [^ ]+' 's/targetSdk = //')"
repo_ndk="$(extract "$REPO_ROOT/android/app/build.gradle.kts" 'ndkVersion = "[^"]+"' 's/ndkVersion = "([^"]+)"/\1/')"

tpl_gradle="$(extract "$GRADLE_UTILS" "const templateDefaultGradleVersion = '[^']+'" "s/.*= '([^']+)'/\1/")"
tpl_agp="$(extract "$GRADLE_UTILS" "const templateAndroidGradlePluginVersion = '[^']+'" "s/.*= '([^']+)'/\1/")"
tpl_kotlin="$(extract "$GRADLE_UTILS" "const templateKotlinGradlePluginVersion = '[^']+'" "s/.*= '([^']+)'/\1/")"
tpl_compile="$(extract "$GRADLE_UTILS" 'const compileSdkVersionInt = [0-9]+' 's/.*= //')"
tpl_minsdk="$(extract "$GRADLE_UTILS" 'const minSdkVersionInt = [0-9]+' 's/.*= //')"
tpl_targetsdk="$(extract "$GRADLE_UTILS" "const targetSdkVersion = '[^']+'" "s/.*= '([^']+)'/\1/")"
tpl_ndk="$(extract "$GRADLE_UTILS" "const ndkVersion = '[^']+'" "s/.*= '([^']+)'/\1/")"

java_raw="$( (java -version 2>&1 || true) | head -1)"
java_version="$(printf '%s' "$java_raw" | sed -E 's/.*"(.*)".*/\1/')"
[ -z "$java_version" ] && java_version="$java_raw"
[ -z "$java_version" ] && java_version="(java not found)"

if [ -n "$flutter_revision" ]; then
    flutter_display="$flutter_version (${flutter_revision:0:10})"
else
    flutter_display="$flutter_version"
fi

row() { printf '%-24s %-26s %s\n' "$1" "$2" "$3"; }

row "Setting" "Repo" "Flutter SDK (template)"
row "Flutter (framework)" "-" "$flutter_display"
row "Dart SDK" "-" "$dart_version"
row "JDK runtime" "system" "$java_version"
row "Gradle wrapper" "$repo_gradle" "$tpl_gradle"
row "AGP" "$repo_agp" "$tpl_agp"
row "Kotlin (KGP)" "$repo_kotlin" "$tpl_kotlin"
if [ -n "$repo_compile_minor" ]; then
    row "compileSdk" "$repo_compile (minor $repo_compile_minor)" "$tpl_compile"
else
    row "compileSdk" "$repo_compile" "$tpl_compile"
fi
row "minSdk" "$repo_minsdk" "$tpl_minsdk"
row "targetSdk" "$repo_targetsdk" "$tpl_targetsdk"
row "NDK" "$repo_ndk" "$tpl_ndk"
