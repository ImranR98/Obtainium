# Obtainium Installation Guide

This document explains how to build and run **Obtainium** using Docker and Flutter. It covers both the **normal** and **F-Droid** flavors.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Docker Setup](#docker-setup)
3. [Running on Device or Emulator](#running-on-device-or-emulator)
4. [Building APKs](#building-apks)
5. [Release Builds & Signing](#release-builds--signing)
6. [APK Locations](#apk-locations)
7. [Tips & Recommendations](#tips--recommendations)

---

## Prerequisites

* Docker installed and running
* Flutter installed (or use Docker container with Flutter preinstalled)
* Android SDK and required Build Tools/NDK (handled by Docker container)
* Emulator or physical device for testing

**Docker resource recommendations:**

* Memory: ≥ 4–6 GB
* CPUs: ≥ 2 cores
* Disk: ≥ 10 GB free

---

## Docker Setup

From the root of the project, build the Docker image and enter the container:

```sh
./docker/mkbuilder.sh && ./docker/builder.sh ./build.sh
```

> Use `sudo` if you run into permission issues.

This sets up a reproducible environment with all necessary dependencies (Flutter, Android SDK, NDK, Build Tools, etc.).

---

## Running on Device or Emulator

### Normal flavor

```sh
flutter run --flavor normal
```

### F-Droid flavor

```sh
flutter run --flavor fdroid
```

> These commands launch the app directly on a connected device or emulator in **debug mode**.

---

## Building APKs

### Build normal flavor

```sh
flutter build apk --debug --flavor normal
```

### Build F-Droid flavor

```sh
flutter build apk --debug --flavor fdroid
```

---

## Release Builds & Signing

When attempting to create a **release** build without a configured release keystore, the build system will display the following warning and fall back to using the **debug** signing configuration:

```
You are trying to create a release build, but a key.properties file was not found.
Falling back to the "debug" signing config.
To sign a release build, a keystore properties file is required.
```

### Configuring a Release Keystore

To properly sign a release build, create a file at:

```
[project]/android/key.properties
```

> A template file named `key.properties.example` is provided in the same directory and can be used as a guide when creating this file.

The file should contain the following properties (do **not** include the angle brackets `< >`, replace the values with your credentials):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=<key alias>
storeFile=<keystore file location>
```

Once this file is present, release builds will be signed using your provided keystore instead of the debug key.

For more details on Android app signing with Flutter, see:

* [https://docs.flutter.dev/deployment/android#sign-the-app](https://docs.flutter.dev/deployment/android#sign-the-app)

## APK Locations

After building, the APKs can be found here:

| Flavor  | APK Path                                             |
| ------- | ---------------------------------------------------- |
| Normal  | `build/app/outputs/flutter-apk/app-normal-debug.apk` |
| F-Droid | `build/app/outputs/flutter-apk/app-fdroid-debug.apk` |

You can install them manually using:

```sh
adb install -r <path-to-apk>
```

---

## Tips & Recommendations

* Ensure Docker has enough memory and CPU resources to avoid Gradle or NDK build failures.
* If you encounter long build times on first run, it is usually Gradle auto-installing missing NDK or Build Tools — this is normal.
* Use `flutter clean` if you switch between flavors to avoid caching issues:

```sh
flutter clean
flutter pub get
```

* Always specify `--flavor` when building or running to match the intended APK variant.

---

*This document is intended to provide clear, reproducible instructions for both contributors and users building Obtainium from source.*
