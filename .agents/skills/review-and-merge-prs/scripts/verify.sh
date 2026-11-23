#!/usr/bin/env bash
# Read-only verification of a PR in a temporary worktree.
#
# Usage: scripts/verify.sh <pr-number> [options]
#
# Options:
#   --translations   translation checks only (code gates skipped)
#   --code           force code gates even if no code paths are detected
#   --build          run flutter build apk --flavor normal
#   --e2e            run ./tool/e2e.sh (requires an attached device)
#   --no-test        skip flutter test
#   --keep           keep the temporary worktree
#   --base REV       base ref for the diff (default origin/main)
#   --worktree DIR   custom worktree directory
#   --help, -h       show this help
#
# Makes no changes to the user's working tree. Logs go to
# /tmp/opencode/obtainium-pr-review/verify/pr-<n>.log.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SKILL_DIR/../../.." &>/dev/null && pwd)"
OUT_ROOT="${OUT_ROOT:-/tmp/opencode/obtainium-pr-review}"
LOG_DIR="$OUT_ROOT/verify"
WT_ROOT="$OUT_ROOT/worktrees"

PR=""
TRANSLATIONS_ONLY=false
FORCE_CODE=false
RUN_BUILD=false
RUN_E2E=false
RUN_TESTS=true
KEEP=false
BASE_OVERRIDE=""
CUSTOM_WT=""

usage() {
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --translations) TRANSLATIONS_ONLY=true ;;
        --code) FORCE_CODE=true ;;
        --build) RUN_BUILD=true ;;
        --e2e) RUN_E2E=true ;;
        --no-test) RUN_TESTS=false ;;
        --keep) KEEP=true ;;
        --base) BASE_OVERRIDE="$2"; shift ;;
        --worktree) CUSTOM_WT="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)
            if [[ -n "$PR" ]]; then
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            PR="$1"
            ;;
    esac
    shift
done

if [[ ! "$PR" =~ ^[0-9]+$ ]]; then
    echo "Usage: scripts/verify.sh <pr-number> [options]" >&2
    exit 1
fi

if [[ -x "$REPO_ROOT/.flutter/bin/flutter" ]]; then
    FLUTTER="$REPO_ROOT/.flutter/bin/flutter"
    DART="$REPO_ROOT/.flutter/bin/dart"
    export PATH="$REPO_ROOT/.flutter/bin:$PATH"
else
    FLUTTER="$(command -v flutter || true)"
    DART="$(command -v dart || true)"
fi
if [[ -z "$FLUTTER" || -z "$DART" ]]; then
    echo "Flutter/Dart not found; see AGENTS.md" >&2
    exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
    echo "gh not found; see AGENTS.md" >&2
    exit 1
fi
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; required for translation checks" >&2
    exit 1
fi
if [[ -d "$REPO_ROOT/.flutter" ]] && ! "$FLUTTER" --version >/dev/null 2>&1; then
    echo "The pinned Flutter at $FLUTTER is not usable; initialise/repair the submodule" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$WT_ROOT"
LOG="$LOG_DIR/pr-$PR.log"
: >"$LOG"

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BASE_REF="${BASE_OVERRIDE:-origin/main}"
if [[ -z "$BASE_OVERRIDE" ]]; then
    git -C "$REPO_ROOT" fetch --quiet origin main
fi
git -C "$REPO_ROOT" fetch --quiet origin "+refs/pull/$PR/head:refs/remotes/origin/pr-$PR"
HEAD_REF="origin/pr-$PR"
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse "$HEAD_REF")"
WT="${CUSTOM_WT:-$WT_ROOT/pr-$PR}"

if [[ -e "$WT" ]]; then
    if git -C "$REPO_ROOT" worktree list --porcelain | grep -Fqx "worktree $WT"; then
        git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
    else
        echo "Refusing to reuse existing path that is not a registered worktree: $WT" >&2
        exit 1
    fi
fi

git -C "$REPO_ROOT" worktree add --detach "$WT" "$HEAD_REF" >/dev/null
MERGE_BASE="$(git -C "$WT" merge-base HEAD "$BASE_REF")"
CHANGED="$(git -C "$WT" diff --name-only "$MERGE_BASE"..HEAD)"
PASS=()
FAIL=()

cleanup() {
    if [[ "$KEEP" == true ]]; then
        echo "Kept worktree: $WT"
        return
    fi
    if git -C "$REPO_ROOT" worktree list --porcelain | grep -Fqx "worktree $WT"; then
        git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

run_step() {
    local name="$1"
    shift
    echo "== $name"
    if "$@" 2>&1 | tee -a "$LOG"; then
        PASS+=("$name")
    else
        FAIL+=("$name")
    fi
}

run_in_wt() {
    local name="$1"
    shift
    echo "== $name"
    if (cd "$WT" && "$@") 2>&1 | tee -a "$LOG"; then
        PASS+=("$name")
    else
        FAIL+=("$name")
    fi
}

{
    echo "PR #$PR"
    echo "repo:        $REPO"
    echo "head:        $HEAD_REF $HEAD_SHA"
    echo "base:        $BASE_REF"
    echo "merge-base:  $MERGE_BASE"
    echo "worktree:    $WT"
    echo "flutter:     $FLUTTER"
    echo "changed:"
    printf '%s\n' "$CHANGED" | sed 's/^/  /'
    echo
} | tee -a "$LOG"

TRANSLATION_CHANGED="$(printf '%s\n' "$CHANGED" | grep -E '^assets/translations/.*\.json$' || true)"
ROOT_TRANSLATION="$(printf '%s\n' "$CHANGED" | grep -E '^[^/]+\.json$' || true)"
CODE_CHANGED="$(printf '%s\n' "$CHANGED" | grep -E '^(lib/|test/|integration_test/|android/|packages/|tool/|pubspec\.(yaml|lock)$)' || true)"

run_step "diff whitespace check" git -C "$WT" diff --check "$MERGE_BASE"..HEAD

RUN_TRANSLATIONS=false
if [[ -n "$TRANSLATION_CHANGED" || -n "$ROOT_TRANSLATION" || -n "$CODE_CHANGED" ]]; then
    RUN_TRANSLATIONS=true
fi

if [[ "$RUN_TRANSLATIONS" == true ]]; then
    if [[ -n "$TRANSLATION_CHANGED" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            run_step "json $file" jq empty "$WT/$file"
        done <<<"$TRANSLATION_CHANGED"
    fi
    run_step "translation checks" node "$SKILL_DIR/scripts/check-translations.mjs" --root "$WT" --base "$MERGE_BASE" --code
    if [[ -n "$TRANSLATION_CHANGED" || -n "$ROOT_TRANSLATION" ]]; then
        run_step "standardize" bash -c 'cd "$1" && node assets/translations/standardize.mjs' _ "$WT"
        run_step "standardize no-op" git -C "$WT" diff --exit-code -- assets/translations
    fi
fi

RUN_CODE="$FORCE_CODE"
if [[ -n "$CODE_CHANGED" ]]; then
    RUN_CODE=true
fi
if [[ "$TRANSLATIONS_ONLY" == true ]]; then
    RUN_CODE=false
    if [[ -n "$CODE_CHANGED" ]]; then
        echo "WARNING: --translations was given but this PR also changes code; code gates were skipped." | tee -a "$LOG"
    fi
fi

if [[ "$RUN_CODE" == true ]]; then
    PUB_CHANGED="$(printf '%s\n' "$CHANGED" | grep -E '^pubspec\.(yaml|lock)$' || true)"
    if [[ -n "$PUB_CHANGED" ]]; then
        run_in_wt "pub get" "$FLUTTER" pub get --enforce-lockfile
    else
        run_in_wt "pub get" "$FLUTTER" pub get
        if ! git -C "$WT" diff --quiet -- pubspec.lock; then
            {
                echo "WARNING: pub get updated pubspec.lock in the worktree. This is treated as"
                echo "pinned-SDK dependency drift, not a PR failure; inspect the diff if the PR"
                echo "changes dependencies."
                git -C "$WT" diff --stat -- pubspec.lock
            } | tee -a "$LOG"
        fi
    fi
    run_in_wt "analyze" "$FLUTTER" analyze
    run_in_wt "format" "$DART" format --set-exit-if-changed .
    if [[ "$RUN_TESTS" == true ]]; then
        run_in_wt "test" "$FLUTTER" test
    fi
    if [[ "$RUN_BUILD" == true ]]; then
        run_in_wt "build apk" "$FLUTTER" build apk --flavor normal
    fi
    if [[ "$RUN_E2E" == true ]]; then
        SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
        ADB="${ADB:-$SDK/platform-tools/adb}"
        if ! "$ADB" get-state >/dev/null 2>&1 && [[ -z "${E2E_DEVICE:-}" ]]; then
            echo "== e2e" | tee -a "$LOG"
            echo "No device attached; start an emulator or set E2E_DEVICE." | tee -a "$LOG"
            FAIL+=("e2e")
        else
            run_in_wt "e2e" env PATH="$REPO_ROOT/.flutter/bin:$PATH" ./tool/e2e.sh
        fi
    fi
fi

{
    echo
    echo "== summary"
    printf 'PASS: %s\n' "${PASS[*]:-(none)}"
    printf 'FAIL: %s\n' "${FAIL[*]:-(none)}"
} | tee -a "$LOG"

if (( ${#FAIL[@]} > 0 )); then
    echo "FAILED: PR #$PR ($LOG)" >&2
    exit 1
fi
echo "PASSED: PR #$PR ($LOG)"
