# Obtainium Installation Guide

This document explains how to build and run **Obtainium** using Docker and Flutter. It covers both the **normal** and **F-Droid** flavors.

---

## Table of Contents

1. [Prerequisites](#prerequisites)  
2. [Docker Setup](#docker-setup)  
3. [Running on Device or Emulator](#running-on-device-or-emulator)  
4. [Building APKs](#building-apks)  
5. [APK Locations](#apk-locations)  
6. [Tips & Recommendations](#tips--recommendations)  

---

## Prerequisites

- Docker installed and running  
- Flutter installed (or use Docker container with Flutter preinstalled)  
- Android SDK and required Build Tools/NDK (handled by Docker container)  
- Emulator or physical device for testing  

**Docker resource recommendations:**  
- Memory: ≥ 4–6 GB  
- CPUs: ≥ 2 cores  
- Disk: ≥ 10 GB free  

---

## Docker Setup

From the root of the project, build the Docker image and enter the container:

```sh
./docker/mkbuilder.sh && ./docker/builder.sh ./build.sh
````

> use sudo if you run into permission issues

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

> These commands launch the app directly on a connected device or emulator in debug mode.

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
