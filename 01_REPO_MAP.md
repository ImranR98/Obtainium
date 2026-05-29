# 01_REPO_MAP.md — Obtainium Repository Map

## Repository Structure

```
obtainium/
├── lib/                          # Dart source code
│   ├── main.dart                 # App entry point (normal flavor)
│   ├── main_fdroid.dart          # App entry point (F-Droid flavor)
│   ├── custom_errors.dart        # Error/warning class definitions
│   ├── app_sources/              # App source implementations (31 files)
│   │   ├── apk4free.dart
│   │   ├── apkcombo.dart
│   │   ├── apkmirror.dart
│   │   ├── apkpure.dart
│   │   ├── aptoide.dart
│   │   ├── codeberg.dart
│   │   ├── coolapk.dart
│   │   ├── directAPKLink.dart
│   │   ├── farsroid.dart
│   │   ├── fdroid.dart
│   │   ├── fdroidrepo.dart
│   │   ├── github.dart
│   │   ├── gitlab.dart
│   │   ├── html.dart             # Generic HTML source (fallback)
│   │   ├── huaweiappgallery.dart
│   │   ├── izzyondroid.dart
│   │   ├── jenkins.dart
│   │   ├── liteapks.dart
│   │   ├── mullvad.dart
│   │   ├── neutroncode.dart
│   │   ├── rockmods.dart
│   │   ├── rustore.dart
│   │   ├── sourceforge.dart
│   │   ├── sourcehut.dart
│   │   ├── telegramapp.dart
│   │   ├── tencent.dart
│   │   ├── uptodown.dart
│   │   └── vivoappstore.dart
│   ├── components/
│   │   ├── custom_app_bar.dart
│   │   ├── generated_form.dart
│   │   └── generated_form_modal.dart
│   ├── pages/
│   │   ├── add_app.dart          # Add new app UI
│   │   ├── app.dart              # Individual app detail page
│   │   ├── apps.dart             # Apps list page
│   │   ├── home.dart             # Home/dashboard page
│   │   ├── import_export.dart    # Backup/restore UI
│   │   └── settings.dart         # Global settings page
│   ├── providers/
│   │   ├── apps_provider.dart    # Core app management (~2663 lines)
│   │   ├── logs_provider.dart
│   │   ├── native_provider.dart
│   │   ├── notifications_provider.dart
│   │   ├── settings_provider.dart
│   │   └── source_provider.dart  # Source implementation factory (~1318 lines)
│   ├── mass_app_sources/
│   │   └── githubstars.dart      # Bulk-import from GitHub stars
│   └── mass_app_sources/
├── android/                      # Android native layer
│   ├── app/build.gradle.kts      # APK build config, signing, flavor dimensions
│   ├── build.gradle.kts
│   ├── gradle/                   # Gradle configuration
│   ├── settings.gradle.kts
│   └── gradle.properties
├── assets/
│   ├── graphics/                 # App icon, logos
│   ├── fonts/                    # Montserrat font
│   ├── translations/              # i18n JSON files per locale
│   ├── ca/                       # Certificate authority data
│   └── screenshots/
├── test/widget_test.dart         # Placebo test (no-op counter test)
├── .github/workflows/
│   ├── release.yml               # Manual APK build + draft release
│   ├── fastlane.yml              # F-Droid deployment
│   └── translation-validate.yaml  # PR translation validation
├── fastlane/                      # F-Droid metadata
├── docker/                        # Docker files
├── pubspec.yaml                  # Flutter dependencies
├── pubspec.lock
├── build.sh                       # Local convenience build script
├── sign.sh                        # APK signing script
├── analysis_options.yaml         # Dart analyzer config (flutter_lints only)
├── CONTRIBUTING.md               # ❌ NOT FOUND
├── LICENSE.txt
├── README.md
└── .metadata
```

## App Sources (Inheritance Hierarchy)

```
AppSource (abstract base)
├── GitHub
├── GitLab
├── Codeberg (Forgejo-compatible)
├── F-Droid
├── IzzyOnDroid
├── SourceHut
├── SourceForge
├── Jenkins
├── GitHub Stars (mass import)
├── APKPure
├── Aptoide
├── Uptodown
├── Huawei AppGallery
├── Tencent App Store
├── vivo App Store
├── RuStore
├── Farsroid
├── CoolApk
├── LiteAPKs
├── RockMods
├── APK4Free
├── APKMirror (track-only)
├── APKCombo
├── Neutron Code
├── Telegram App
├── Direct APK Link
├── HTML (generic fallback)
└── Mullvad
```

## Key Classes / Functions

### apps_provider.dart (~2663 lines)
| Symbol | Type | Purpose |
|---|---|---|
| `AppInMemory` | class | In-memory app state (download progress, icon, installed info, signers) |
| `DownloadedApk` | class | Downloaded APK file wrapper |
| `DownloadedDir` | class | Extracted archive directory |
| `generateStandardVersionRegExStrings()` | function | Generates version detection regex patterns |
| `findStandardFormatsForVersion()` | function | Matches version strings against standard formats |
| `downloadFileWithRetry()` | function | Download with exponential retry on ClientException |
| `downloadFile()` | function | Core download with range/resume support, progress callbacks |
| `checkPartialDownloadHashDynamic()` | function | Verifies file integrity by sampling hash at decreasing offsets |
| `checkETagHeader()` | function | ETag-based change detection without full download |
| `hashListOfLists()` | function | SHA-256 hash of encoded data structure |

### source_provider.dart (~1318 lines)
| Symbol | Type | Purpose |
|---|---|---|
| `APKDetails` | class | Version, URLs, names, release date, changelog |
| `AppNames` | class | author + name pair |
| `AppSource` | class | Abstract base for all app sources |
| `SourceProvider` | class | Factory to instantiate source by URL pattern |

### custom_errors.dart
| Symbol | Type | Purpose |
|---|---|---|
| `ObtainiumError` | class | Base error class |
| `RateLimitError` | class | API rate limit exceeded |
| `NoReleasesError` | class | No releases found for app |
| `NoAPKError` | class | No APK in release |
| `NoVersionError` | class | Cannot parse version from release |
| `DowngradeError` | class | Trying to install older version |
| `IDChangedError` | class | Package ID mismatch after install |
| `MultiAppMultiError` | class | Aggregates errors across multiple apps |

## Dependencies of Note (Security-Relevant)

| Package | Version | Risk |
|---|---|---|
| `http` | ^1.6.0 | HTTP client with `allowInsecure` flag |
| `webview_flutter` | ^4.13.1 | Embedded WebView (attack surface) |
| `permission_handler` | ^12.0.1 | Runtime permissions |
| `android_package_installer` | git (custom fork) | APK installation |
| `shizuku_apk_installer` | git (custom fork) | Shizuku-based installation |
| `shared_storage` | git (questionable maintenance) | Storage access |
| `bcrypt` | ^1.2.0 | Password hashing (if used for any auth) |
| `crypto` | ^3.0.7 | SHA-256 for cert hashes |

## No-op / Placebo Files
- `test/widget_test.dart` — Default Flutter counter test, not a real test
- `CONTRIBUTING.md` — Does not exist
- `.gitmodules` — Present but no submodules checked out
