# 02_SETUP_AND_BASELINE.md — Obtainium Setup & Baseline

## Prerequisites

### System Requirements
- Flutter SDK >=3.38.0 (installed in `.flutter/` submodule or globally)
- Dart SDK ^3.10.0
- Java 17+ (Android build)
- Android SDK (Android build tools, platform tools)
- `jq` (for translation validation CI)

### Initial Setup Commands

```bash
cd /root/hard-pr-1/repos/obtainium/

# Initialize git submodules (Flutter is a submodule in .flutter/)
git submodule update --init

# Fetch Flutter from submodule
cd .flutter && git fetch && git checkout stable && cd ..

# Or use global Flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install dependencies
flutter pub get

# Verify setup
flutter doctor -v
```

### Android Signing
For release builds, create `android/key.properties`:
```
storePassword=<keystore_password>
keyPassword=<key_password>
keyAlias=<key_alias>
storeFile=<path/to/keystore>
```

Without `key.properties`, the build script emits a warning and produces unsigned APKs.

---

## Dependencies

### Core
| Package | Version | Purpose |
|---|---|---|
| flutter | >=3.38.0 | Framework |
| provider | ^6.1.5 | State management |
| http | ^1.6.0 | HTTP client |
| sqflite | ^2.4.2 | Local DB |
| shared_preferences | ^2.5.5 | Key-value storage |

### App Installation / System
| Package | Version | Purpose |
|---|---|---|
| android_package_installer | git (custom fork ImranR98) | APK installer |
| android_package_manager | git (custom fork ImranR98) | Package manager |
| shizuku_apk_installer | git (re7gog) | Shizuku-based install |
| permission_handler | ^12.0.1 | Runtime permissions |
| share_plus | ^12.0.2 | Share APK files |

### Networking / Parsing
| Package | Version | Purpose |
|---|---|---|
| webview_flutter | ^4.13.1 | In-app WebView |
| html | ^0.15.6 | HTML parsing for sources |
| flutter_charset_detector | ^5.0.0 | Charset detection |

### Background / Notifications
| Package | Version | Purpose |
|---|---|---|
| flutter_fgbg | ^0.8.0 | Foreground/background detection |
| flutter_local_notifications | ^21.0.0 | Local notifications |
| background_fetch | ^1.6.0 | Background update checks |
| flutter_foreground_task | ^9.2.2 | Persistent foreground tasks |

### UI / Theming
| Package | Version | Purpose |
|---|---|---|
| cupertino_icons | ^1.0.9 | iOS icons |
| animations | ^2.1.2 | UI animations |
| flex_color_picker | ^3.8.0 | Color picker |
| dynamic_system_colors | ^1.9.0 | Material You dynamic colors |
| flutter_typeahead | ^6.0.0 | Search autocomplete |
| markdown | ^7.3.1 | Markdown rendering |
| flutter_markdown_plus | ^1.0.7 | Enhanced markdown |

### i18n
| Package | Version | Purpose |
|---|---|---|
| easy_localization | ^3.0.8 | Internationalization |

### Security / Crypto
| Package | Version | Purpose |
|---|---|---|
| crypto | ^3.0.7 | SHA-256 certificate hashing |
| bcrypt | ^1.2.0 | Password hashing |
| app_links | ^7.0.0 | Deep linking |
| android_intent_plus | ^6.0.0 | Android intent launching |

### Archives / Files
| Package | Version | Purpose |
|---|---|---|
| flutter_archive | ^6.0.4 | ZIP/XAPK extraction |
| file_picker | ^11.0.2 | File selection |
| path_provider | ^2.1.5 | App directories |
| shared_storage | git (AlexBacich, questionable maint.) | Storage access |

### Other
| Package | Version | Purpose |
|---|---|---|
| equations | ^6.0.0 | Math expression parsing |
| battery_plus | ^7.0.0 | Battery state |
| device_info_plus | ^12.4.0 | Device info |
| connectivity_plus | ^7.1.1 | Network status |
| android_system_font | git (re7gog) | System font access |

---

## Build Commands

### Full Release Build (Both Flavors)
```bash
# Remove old APKs
rm ./build/app/outputs/flutter-apk/* 2>/dev/null

# Build normal flavor (combined + split per ABI)
flutter build apk --flavor normal
flutter build apk --split-per-abi --flavor normal
# Rename outputs: app-normal-release.apk → app-release.apk
for file in build/app/outputs/flutter-apk/app-*normal*.apk*; do mv "$file" "${file//-normal/}"; done

# Build F-Droid flavor
flutter build apk --flavor fdroid -t lib/main_fdroid.dart
flutter build apk --split-per-abi --flavor fdroid -t lib/main_fdroid.dart

# Sign APKs with GPG (from build.sh)
# gpg --sign --detach-sig build/app/outputs/flutter-apk/*.sha1
```

### Debug Build
```bash
flutter build apk --flavor normal --debug
flutter build apk --flavor fdroid --debug -t lib/main_fdroid.dart
```

### Analysis
```bash
flutter analyze  # Uses analysis_options.yaml (flutter_lints only)
```

---

## Android Configuration

### minSdk / targetSdk
- **minSdk**: 26 (Android 8.0 Oreo)
- **targetSdk**: Flutter default (latest stable)
- **compileSdk**: Flutter default

### ABI Split Codes
| ABI | Code |
|---|---|
| x86_64 | 1 |
| armeabi-v7a | 2 |
| arm64-v8a | 3 |

Version code formula: `variant.versionCode * 10 + abiCode`

### Product Flavors
- **normal**: standard build (no suffix)
- **fdroid**: F-Droid build (`.fdroid` suffix)

### Core Library Desugaring
Enabled (`coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`) — required for Java 8+ APIs on older Android.

---

## Baseline / Cannot Run

**Flutter is not installed** in this environment, so no `flutter pub get`, `flutter analyze`, or builds can be executed.

### What Was Tested

| Check | Result |
|---|---|
| Flutter available | ❌ Not installed |
| Java available | ⚠️ Unknown |
| Android SDK | ⚠️ Unknown |
| `flutter pub get` | ❌ Not run |
| `flutter analyze` | ❌ Not run |
| Build artifacts | ❌ None |
| Tests | ⚠️ `test/widget_test.dart` is a placebo counter test (no real test coverage) |

### What Could Be Verified
- Downloaded and inspected `pubspec.yaml` ✅
- Downloaded and inspected `build.gradle.kts` ✅
- Downloaded and inspected source files ✅
- Ran `gh` commands for issues/PRs ✅
- Inspected CI workflows ✅
- Inspected `analysis_options.yaml` ✅

---

## CI/CD Baseline

### release.yml
- **Trigger**: Manual workflow dispatch (`workflow_dispatch`)
- **Beta flag**: Boolean input
- **Steps**: checkout → flutter-action → setup-java → extract version → build APKs → save artifacts → create tag → create draft release
- **APK outputs**: `build/app/outputs/flutter-apk/` (unsigned, per-ABI splits)
- **Tagging**: Uses `mathieudutour/github-tag-action` with extracted version
- **Release**: Draft only, with auto-generated release notes

### fastlane.yml
- F-Droid deployment automation (metadata in `fastlane/metadata/`)

### translation-validate.yaml
- Validates changed translation JSONs in PRs using `jq empty`
- Only triggers on PR open/sync/reopen
- Only checks changed files (`git diff --name-only`)

---

## Observables / Health Indicators

| Indicator | Value |
|---|---|
| Tests | ❌ Placebo only — no real test coverage |
| Lint rules | ⚠️ Only `flutter_lints` — minimal enforcement |
| CONTRIBUTING.md | ❌ Does not exist |
| Security policy | ❌ Does not exist |
| Deprecation warnings in code | None observed in scanned files |
| Known TODOs in source | ⚠️ Several (pubspec.yaml: android_package_installer, android_package_manager, shared_storage) |
