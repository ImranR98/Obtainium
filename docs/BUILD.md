# Building Obtainium

Step-by-step instructions to set up a working environment and produce APKs,
matching what CI (`.github/workflows/release.yml`) and the repo's own
`build.sh` / `docker/` tooling do. For architecture and coding conventions see
[`DEVELOPER_GUIDE.md`](./DEVELOPER_GUIDE.md).

- [1. Prerequisites](#1-prerequisites)
- [2. Get the source](#2-get-the-source)
- [3. One-time environment setup](#3-one-time-environment-setup)
- [4. Everyday commands](#4-everyday-commands)
- [5. Building release APKs (`build.sh`)](#5-building-release-apks-buildsh)
- [6. Reproducible/CI-identical builds (Docker)](#6-reproducibleci-identical-builds-docker)
- [7. Signing release builds](#7-signing-release-builds)
- [8. Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites

Obtainium and Android/Flutter tooling are large, well-documented projects —
follow their official install guides rather than a copy here, which would go
stale:

- **Flutter** — [Install guide](https://docs.flutter.dev/get-started/install).
  You usually don't need to do this separately: this repo pins its own Flutter
  version via a git submodule (`.flutter/`), see step 3. Only install Flutter
  yourself if you'd rather use a system-wide copy.
- **Android SDK** — normally provided by
  [Android Studio](https://developer.android.com/studio), or install just the
  [command-line tools](https://developer.android.com/tools/sdkmanager) if you
  don't want the IDE. Android Gradle Plugin (AGP) will auto-download the
  specific platform/build-tools/NDK versions this project pins the first time
  you build, as long as `sdkmanager` licenses are accepted (step 3).
- **JDK 17 or newer** (Temurin/Adoptium recommended — CI and the Docker image
  both use **Temurin 21**, so that's the safest match).
  [Adoptium downloads](https://adoptium.net/).
- **Git**, with submodule support (any reasonably recent git has this).

Verify what you have:

```bash
flutter doctor -v
java -version
git --version
```

## 2. Get the source

```bash
git clone https://github.com/<you>/Obtainium.git
cd Obtainium
git submodule update --init --recursive   # fetches the pinned Flutter checkout into .flutter/
```

If you already cloned without `--recursive`, just run the `submodule update`
line above from the repo root.

## 3. One-time environment setup

### 3.1 Flutter SDK

Prefer the pinned submodule — it's what CI, `build.sh`, and the Docker image
all use, so your build matches theirs exactly:

```bash
export PATH="$PATH:$(pwd)/.flutter/bin"
flutter --version
```

Add that `export` line to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) so
it's available in every new shell, or prefix individual commands with it.

If you'd rather use a system-wide Flutter install instead, make sure it's on
the `stable` channel and reasonably up to date (`flutter channel stable &&
flutter upgrade`); nothing else below changes.

### 3.2 `local.properties`

The Android Gradle project needs to know where your Flutter SDK lives. Create
`android/local.properties` (this file is git-ignored):

```properties
flutter.sdk=/absolute/path/to/Obtainium/.flutter
```

(Point this at your system Flutter install instead if you're using one.)
Android Studio creates this automatically if you open the project there; the
command line does not.

### 3.3 Android SDK licenses / components

```bash
sdkmanager --licenses
sdkmanager "platform-tools"
```

You don't need to manually install a specific platform, build-tools, or NDK
version — AGP resolves and downloads exactly what `android/app/build.gradle.kts`
pins (currently NDK `28.2.13676358`) the first time you build.

### 3.4 ReVanced patching support (`normal` flavor only)

The `normal` build flavor depends on `app.revanced:patcher-android` and
`app.revanced:library-android`, which back the ReVanced patch-config feature
(patch selection, keystore signing, patch application — see
`android/app/src/normal/kotlin/dev/imranr/obtainium/revanced/`). These
packages are **only published to GitHub Packages**, which — unlike Maven
Central — requires authentication even for public, unauthenticated *read*
access. Without this, `normal`-flavor builds fail to resolve dependencies; the
`fdroid` flavor is unaffected (it never links these packages at all — see
`RevancedIntegration` in the same directory, which is a no-op stub on that
flavor).

1. Create a GitHub [Personal Access Token](https://github.com/settings/tokens)
   with the **`read:packages`** scope (a classic PAT is simplest; a fine-grained
   token needs read access to Packages). No specific repo access is required —
   read access to public packages is enough.
2. Provide it to Gradle, either:
   - **Persistently**, in `~/.gradle/gradle.properties` (create it if it
     doesn't exist):
     ```properties
     githubPackagesUsername=<your GitHub username>
     githubPackagesPassword=<your PAT>
     ```
   - **Per-shell/CI**, as environment variables instead:
     ```bash
     export ORG_GRADLE_PROJECT_githubPackagesUsername=<your GitHub username>
     export ORG_GRADLE_PROJECT_githubPackagesPassword=<your PAT>
     ```

Building only the `fdroid` flavor (`--flavor fdroid`) never needs this.

### 3.5 Known gap: aapt2 native libraries

The patch engine (`normal` flavor) resolves a bundled `aapt2` binary at
runtime from `android/app/src/normal/jniLibs/<abi>/libaapt2obtainium.so` (see
`Aapt.kt`). **These prebuilt binaries are not currently checked into the
repo** — actual patch *application* will fail at runtime until they're added,
one per supported ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`, matching
`abiCodes` in `android/app/build.gradle.kts`). This does not block compiling
the app or using every other feature (keystore management, patch selection
UI, general app tracking/updating) — only the actual "apply patches to this
APK" step needs it.

## 4. Everyday commands

Run these from the repo root after the one-time setup above. Assumes the
pinned Flutter is on your `PATH` (step 3.1).

```bash
flutter pub get                          # fetch/update Dart packages — run after every pull that touches pubspec.yaml
flutter analyze                          # static analysis — must be clean before opening a PR
dart format --set-exit-if-changed .      # formatting check — run before opening a PR
flutter run                              # run on a connected device/emulator (normal flavor, debug)
flutter build apk --flavor normal        # debug/profile/release APK, normal flavor
flutter build apk --flavor fdroid -t lib/main_fdroid.dart   # fdroid flavor (different entry point!)
flutter build apk --split-per-abi --flavor normal           # smaller per-ABI APKs instead of one universal APK
```

Notes:

- The `fdroid` flavor **must** be built with `-t lib/main_fdroid.dart` — that
  alternate entry point is what sets `isFdroidBuild = true` (see
  `lib/main_fdroid.dart`). Building `--flavor fdroid` without `-t` runs the
  normal entry point in the fdroid-flavored Android shell, which is not what
  you want.
- `flutter build apk` defaults to a `--release` build without a
  `key.properties` present, output APKs are **unsigned** — this is
  intentional (see step 7) and matches CI.
- There's a repo-wide, currently-necessary workaround for a non-reproducible
  build ID Flutter's `libdartjni.so` embeds; `build.sh` and CI both run this
  before building — you shouldn't need it for local debug builds, only for
  reproducible/release ones (it's included in `build.sh`, see below).
- No automated test suite exists yet — `flutter analyze` +
  `dart format --set-exit-if-changed .` are the whole local CI gate.

## 5. Building release APKs (`build.sh`)

`./build.sh` is the maintainer convenience script that does a full clean
release build of both flavors (normal + fdroid, universal + split-per-ABI),
applies the reproducible-build-id workaround, and stages the output. Two
modes:

```bash
./build.sh          # sync: fetch/merge origin/main, update the Flutter submodule + a global ~/flutter if present, then build
./build.sh build    # build only: skip the sync step, just build with what's already checked out
```

Read through it before running it the first time — it pushes to `origin`,
upgrades Flutter in place, and rsyncs output to `~/Downloads/Obtainium-build/`,
none of which you may want for a one-off local build. For most contributors,
the individual commands in section 4 are what you actually want; `build.sh`
is closer to "how the maintainer cuts a release."

## 6. Reproducible/CI-identical builds (Docker)

`docker/` provides a toolchain image that matches CI's environment exactly
(Ubuntu 24.04, Temurin 21, AGP-managed Android SDK/NDK) without needing any of
section 1's prerequisites installed on your own machine — only Docker itself.
Flutter still comes from the repo's pinned submodule (mounted at runtime), not
the image, so the Flutter version stays identical to what `build.sh`/CI use.

```bash
./docker/mkbuilder.sh                                        # build the toolchain image (once, or after Dockerfile changes)
./docker/builder.sh                                           # drop into an interactive shell inside the image
./docker/builder.sh flutter build apk --release --flavor normal   # run a single command non-interactively
./docker/builder.sh ./build.sh build                          # run the full release build non-interactively
```

`docker/builder.sh` mounts the repo into the container and persists
`data/home/` (git-ignored) as the container's `$HOME`, so Gradle/pub caches
survive between runs instead of re-downloading every time.

The GitHub Packages credentials from step 3.4 still apply inside the
container — either bake them into `data/home/.gradle/gradle.properties`
(persists across container runs) or pass them through as env vars, e.g.:

```bash
docker run ... -e ORG_GRADLE_PROJECT_githubPackagesUsername=... -e ORG_GRADLE_PROJECT_githubPackagesPassword=...
```

(or export them in your shell before invoking `docker/builder.sh` — Docker
does not forward host env vars into the container automatically, so you'd
need to add `-e` passthroughs to `docker/builder.sh` yourself if you want that
instead of the gradle.properties approach.)

## 7. Signing release builds

Release APKs from `flutter build apk --release` are **unsigned** unless
`android/key.properties` exists (git-ignored, not present by default). Two
ways to sign:

**A. Gradle-side, at build time** — create `android/key.properties`:

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=<key alias>
storeFile=<path to your .jks/.keystore file>
```

With this present, `flutter build apk --release` produces already-signed
APKs, and the "no key.properties" warning in `build.gradle.kts` output goes
away.

**B. Separately, after the fact** — `./sign.sh <path-to-keystore> <build-dir>`
signs already-built `*-release*.apk` files in `<build-dir>` using `apksigner`
from your `$ANDROID_HOME/build-tools`, and detached-GPG-signs the resulting
SHA-256 hash. This is what CI/`build.sh` use (CI ships unsigned APKs as build
artifacts; maintainers sign them separately with their release key). You'll
be prompted for the keystore password (read via `$KEYSTORE_PASSWORD`, not a
CLI arg, so it doesn't end up in shell history):

```bash
./sign.sh /path/to/release.keystore build/app/outputs/flutter-apk
```

Note: this signs Obtainium's own **release APK** (the app itself). It is
unrelated to the separate ReVanced signing keystore introduced for patched
third-party APKs (Settings → ReVanced patching in the app, or
`KeystoreManager.kt` natively) — don't confuse the two.

## 8. Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| Gradle fails resolving `app.revanced:*` with a 401/403 | GitHub Packages credentials missing/wrong — see step 3.4. Only affects `--flavor normal`. |
| `flutter.sdk not set in local.properties` | Create `android/local.properties` per step 3.2. |
| Patch-config UI works but "apply patches" fails at runtime with an aapt2-related error | Expected until the native `libaapt2obtainium.so` binaries are added — see step 3.5. Not a build-config problem. |
| `fdroid` flavor behaves like `normal` (e.g. checks for Obtainium's own updates) | You built without `-t lib/main_fdroid.dart` — `isFdroidBuild` is only set by that entry point. |
| Non-reproducible build ID / hash mismatch vs. an official release | Make sure you've applied the `libdartjni.so --build-id=none` sed workaround (see `build.sh`) before building, or just use `./build.sh` / Docker, which already do this. |
| `sdkmanager: command not found` | It ships inside the Android command-line tools / Android Studio's SDK manager, under `cmdline-tools/latest/bin/`; make sure that's on your `PATH` (see the Dockerfile for a working example). |
