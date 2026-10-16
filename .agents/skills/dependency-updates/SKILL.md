---
name: dependency-updates
description: Update Obtainium's Flutter SDK submodule to the latest stable and align the Android toolchain (Gradle, AGP, Kotlin, compileSdk, NDK, JDK), then update Flutter packages — fixing build/test fallout and committing each phase separately. Use when asked to update Flutter, upgrade the Android toolchain, bump dependencies/packages, or run the dependency-update workflow.
compatibility: Requires network access, the pinned `.flutter` submodule, an Android SDK and JDK (see AGENTS.md), and enough time/disk for engine artifacts and Gradle downloads. Read AGENTS.md at the repo root first; its hard rules apply throughout.
---

# Dependency Updates

Two phases, each ending in its own commit:

1. **Toolchain**: advance the `.flutter` submodule to the latest stable, read the changelog for
   breaking changes, align the Android-level dependencies with what the new Flutter needs, and
   prove the app still builds.
2. **Packages**: upgrade the pub dependencies, fix the fallout, and prove the app builds and
   tests pass.

**Read `AGENTS.md` first.** Its hard rules apply here, with one carve-out: this workflow is
allowed (and expected) to advance the `.flutter` submodule pointer. The flat ban on changing
the version in `pubspec.yaml` still applies — the maintainer bumps it at release time.

Never downgrade an intentionally-ahead value. This repo deliberately keeps Gradle, AGP,
Kotlin, and compileSdk newer than Flutter's template (see
`references/toolchain-checks.md` for why and for the exact current deviations). Only bump
things below Flutter's requirement/recommendation or needed by plugins. If the new Flutter is
hard-incompatible with an ahead-of-recommendation value, stop and ask the user before changing
it.

## Phase 0 — Preflight

- Run from the repo root. The working tree must be clean (`git status --porcelain`); if not,
  ask the user before proceeding — the two phase commits must contain only upgrade changes.
- Confirm the `.flutter` submodule is initialised and on `stable`:
  `git -C .flutter status`, `git -C .flutter branch --show-current`.
- Resolve Flutter, the Android SDK, and the JDK per `AGENTS.md`; note the JDK because the new
  Flutter may raise its minimum. Network is required for the submodule fetch, engine/Dart
  artifacts, Gradle/AGP downloads, and pub.
- Take a before snapshot: `scripts/toolchain-report.sh`. Keep a scratch log at
  `/tmp/obtainium-deps/<date>/notes.md` for versions, decisions, and command results.
- Use generous timeouts for the commands below (submodule fetch, first build, Gradle downloads
  can run many minutes; do not let a 2-minute default kill them).

## Phase 1 — Pick the target and read the changelog first

```bash
git -C .flutter fetch origin stable
git -C .flutter log --oneline HEAD..origin/stable | head
git -C .flutter diff HEAD..origin/stable -- CHANGELOG.md
```

- If `origin/stable` is already at `HEAD`, Flutter is current: say so and skip to Phase 6
  (package updates), unless the user asked for a specific toolchain change.
- Read the changelog entries (and Flutter's breaking-changes/release-notes pages when the
  changelog is vague) for: new Android/Gradle/AGP/Kotlin/Java requirements, forced migrations
  (for example the built-in Kotlin opt-in at Flutter 3.50), and deprecations that could touch
  this app. Recent history: `f3afcfdc` migrated to built-in Kotlin ahead of the 3.50 warning,
  and `11161084` upgraded the Android toolchain for JDK 25 support.
- Summarise the risks and any forced migration to the user before proceeding. If a migration
  is not clearly safe, agree on the plan first.

## Phase 2 — Update the Flutter submodule

The submodule is a checkout of `flutter/flutter` on branch `stable`, so:

```bash
git -C .flutter checkout stable
git -C .flutter pull --ff-only
grep frameworkVersion .flutter/bin/cache/flutter.version.json   # verify the new version
./.flutter/bin/flutter --version                                 # fetches matching artifacts
git submodule status
```

- `build.sh` (`git submodule update --remote`, then fetch/checkout stable/pull, then
  `FLUTTER_GIT_URL="https://github.com/flutter/flutter/" ./bin/flutter upgrade`) is the
  fallback if `pull --ff-only` fails because the branch moved or the tree is dirty.
- Do not commit yet. The pointer will be recorded in Phase 5 together with the toolchain.

## Phase 3 — Align the Android toolchain

Primary sources of truth, in order:

1. `./.flutter/bin/flutter analyze --suggestions` — Flutter's own project review.
2. `./.flutter/bin/flutter doctor -v` — JDK/SDK/Android toolchain status.
3. The SDK constants (`gradle_utils.dart`, `FlutterExtension.kt`) — see
   `references/toolchain-checks.md` for exact paths and fields.
4. `flutter build` warnings (KGP, `android.builtInKotlin`, `android.newDsl`, deprecations).

Check each of these against the new Flutter and update only if needed:

- **Gradle wrapper** — `android/gradle/wrapper/gradle-wrapper.properties` (only the properties
  file is tracked; the jar/wrapper scripts are gitignored).
- **AGP and Kotlin/KGP** — `android/settings.gradle.kts` plugin versions.
- **compileSdk / minSdk / targetSdk / NDK** — `android/app/build.gradle.kts`. Keep the
  versioned compileSdk form and its F-Droid comment unless the new Flutter changes the
  requirement; targetSdk tracks `flutter.targetSdkVersion`.
- **Gradle properties / DSL migrations** — `android/gradle.properties` and the `kotlin { }`
  block in `android/app/build.gradle.kts`, as the maintainer did for built-in Kotlin.
- **`desugar_jdk_libs`** — bump only if the new toolchain requires it.

Java: the app compiles with Java 17 source/target and that matches Flutter's template. The
runtime JDK must satisfy the new AGP/Gradle: AGP 8.0–9.2 needs Java ≥ 17 and Gradle ≥ 9.1
supports JDK 25 (see the compatibility tables in `references/toolchain-checks.md`). If the
local JDK is too old, offer to help the user install a suitable version; if the current JDK is
still compatible, leave it and note that in the report. Never change the system JDK unasked.

If the new Flutter changes the required JDK or tool versions, update the CI and Docker builder
to match in the same commit: `.github/workflows/release.yml` (setup-java), `docker/Dockerfile`
(JAVA_HOME/Temurin, SDK packages), and `docker/builder.sh` if paths/versions are referenced.

Android SDK components: verify the required platform/build-tools/NDK are installed
(`<sdk>/platforms`, `build-tools`, `ndk`; `sdkmanager --list_installed`). Ask the user before
installing system-level components or accepting licenses.

## Phase 4 — Build gate #1 (before touching packages)

```bash
flutter pub get
flutter analyze                            # must be clean
dart format --set-exit-if-changed .
flutter test
flutter build apk --flavor normal          # full release build, the real gate
```

- Use `flutter build apk --debug` while iterating for speed, but finish on the release build
  of the `normal` flavour.
- Fix every failure caused by the upgrade (migrator suggestions, Kotlin DSL changes, plugin
  compatibility, new analyzer rules). If something cannot be fixed without a decision that is
  out of scope (for example a plugin that blocks the new Flutter entirely), stop and report —
  do not commit a broken toolchain, and offer to revert the submodule update.
- If architecture/commands/conventions changed, update `docs/DEVELOPER_GUIDE.md` in this
  commit.

## Phase 5 — Commit the toolchain

- Stage explicitly: `git add .flutter android/ .github/ docker/ docs/ ...` (whatever actually
  changed). Never `git add -A`.
- Subject style: `Update Flutter to <version> and Android toolchain` (sentence case, no issue
  reference unless the upgrade closes one).
- Body: the version deltas (Flutter, Gradle, AGP, Kotlin, compileSdk, NDK, JDK if changed) and
  exactly what was verified (`flutter analyze`, unit tests, release build, e2e if run).
- Do not bump `pubspec.yaml`'s version. Do not push.

## Phase 6 — Update the Flutter packages

```bash
flutter pub outdated
flutter pub upgrade --tighten --major-versions
git diff pubspec.yaml pubspec.lock
```

- `--tighten --major-versions` is the maintainer's own command (it sits commented in
  `build.sh`); it updates constraints and the lockfile to the newest resolvable versions.
- Review the `pubspec.yaml` diff carefully. The git dependencies are intentionally pinned to
  commit SHAs with TODO notes (`android_package_installer`, `android_package_manager`,
  `shared_storage`, `android_system_font`, `shizuku_apk_installer`). If pub changed a `ref:`,
  restore the pin. Leave the `environment` bounds alone unless resolution requires a change.
- Fix fallout package by package: run `dart fix --apply`, handle API/behavior changes, adapt
  to new lint rules from `flutter_lints`, and re-run tests as you go.
- If a package cannot be fixed reasonably: revert just that package to its previous version
  (restore its constraint and run `flutter pub get`), record why, continue with the rest, and
  call it out in the report and commit body. Never leave the tree in a broken state.
- Do not bump the app version.

## Phase 7 — Verify and commit the packages

```bash
flutter analyze
dart format --set-exit-if-changed .
flutter test
flutter build apk --flavor normal
```

- If a device or emulator is already attached (`adb devices`), run the relevant
  `./tool/e2e.sh` suites too. Do not demand one just for a package bump; if runtime behavior
  is plausibly affected and no device is attached, say what remains unverified.
- Commit separately: subject like `Update packages`. Body: notable major bumps, fixes applied,
  held-back packages with reasons, and the exact verification performed.
- Never bump the version, never push.

## Phase 8 — Report

- Before/after table: Flutter + Dart, Gradle, AGP, Kotlin, compileSdk/minSdk/targetSdk, NDK,
  JDK runtime, and the noteworthy package bumps.
- The two commit hashes, and anything held back (with reasons).
- Next steps for the maintainer: bump the version, cut the release, and any F-Droid or
  device-only checks that remain.

## Gotchas

- Run `scripts/toolchain-report.sh` before and after; it prints the repo values next to
  Flutter's template constants so mismatches are obvious.
- `flutter analyze --suggestions` is the authoritative recommendation source; the constants
  files are the fallback and explain the numbers.
- The repo is intentionally ahead of the template (Gradle/AGP/Kotlin/compileSdk); a
  "mismatch" against the template is not automatically a problem. Never downgrade.
- Wrapper scripts and `gradle-wrapper.jar` are gitignored; only
  `gradle-wrapper.properties` is tracked.
- The first build after a Flutter bump re-downloads engine artifacts and Gradle
  distributions; allow long timeouts and good network. Do not run `flutter clean` unless a
  stale build is actually suspected.
- If the upgrade reveals a forced migration that touches app code (like the material_ui
  migration in `f3afcfdc`), that is fine to do here, but keep it in the toolchain commit and
  state it in the body.
