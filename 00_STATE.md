# 00_STATE.md — Obtainium Project State

## Fork Status
- **Target**: Fork ImranR98/Obtainium to Arvuno organization
- **Result**: FAILED — Arvuno is a user account, not an organization (HTTP 422)
- **Workaround**: Cloned ImranR98/Obtainium directly to `/root/hard-pr-1/repos/obtainium/`
- **Repo URL**: https://github.com/ImranR98/Obtainium
- **Local path**: `/root/hard-pr-1/repos/obtainium/`
- **Note**: Arvuno fork not possible for user accounts; would need organization-level fork

## Project Overview
- **Name**: Obtainium
- **Type**: Android mobile app (Flutter/Dart)
- **Purpose**: Install and update Android apps directly from release sources (GitHub, GitLab, APKPure, etc.)
- **Package ID**: `dev.imranr.obtainium`
- **Version**: 1.4.3+2335
- **License**: Proprietary (LICENSE.txt)
- **Min SDK**: 26 (Android 8.0)
- **Target SDK**: Flutter default (latest)

## Tech Stack
| Layer | Technology |
|---|---|
| Framework | Flutter 3.38.0+ / Dart SDK ^3.10.0 |
| State Management | Provider ^6.1.5 |
| Local Storage | sqflite ^2.4.2, shared_preferences ^2.5.5 |
| HTTP | http ^1.6.0 (IOClient with allowInsecure option) |
| Notifications | flutter_local_notifications ^21.0.0 |
| Background Tasks | flutter_fgbg ^0.8.0, background_fetch ^1.6.0, flutter_foreground_task ^9.2.2 |
| Internationalization | easy_localization ^3.0.8 |
| Archive Extraction | flutter_archive ^6.0.4 |
| APK Installation | android_package_installer (custom fork), shizuku_apk_installer |
| HTML Parsing | html ^0.15.6 |
| WebView | webview_flutter ^4.13.1 |
| Crypto | crypto ^3.0.7, bcrypt ^1.2.0 |

## Build Variants
- `normal` — Standard Google Play-compatible build
- `fdroid` — F-Droid compatible build (applicationId: `dev.imranr.obtainium.fdroid`)

## CI/CD
- **release.yml**: Manual dispatch trigger, builds APKs (normal & fdroid flavors), creates draft release with tag
- **fastlane.yml**: F-Droid deployment automation
- **translation-validate.yaml**: Validates modified translation JSONs on PR

## Key Paths
```
/root/hard-pr-1/repos/obtainium/
├── lib/
│   ├── app_sources/        # 31 source implementations (GitHub, GitLab, APKPure, etc.)
│   ├── components/         # UI components (custom_app_bar, generated_form*)
│   ├── pages/             # 6 pages (apps, app, add_app, home, settings, import_export)
│   ├── providers/          # 5 providers (apps, logs, native, notifications, settings, source)
│   ├── main.dart
│   └── main_fdroid.dart
├── android/app/build.gradle.kts  # Android build config
├── pubspec.yaml
├── test/widget_test.dart         # Placebo test (counter test, not real)
├── assets/translations/          # i18n JSON files
├── .github/workflows/
└── build.sh / sign.sh           # Local build scripts
```

## Current Activity
- **Open Issues**: ~90+ (high volume bug/enhancement tracker)
- **Open PRs**: 8 active
- **Last release**: v1.4.3+2335 (May 2026)
- **Contributors**: Community-driven with heavy i18n contributions

## Security Posture
- Web scraping-based app sources (easily breakable per README)
- Personal Access Token (PAT) storage for GitHub sources
- No certificate pinning (Issue #2916 — OPEN)
- SHA-256 certificate hash verification for installed apps
- Uses `allowInsecure` flag to permit HTTP for dev/ITFs
- Reproducible builds claimed for F-Droid flavor
