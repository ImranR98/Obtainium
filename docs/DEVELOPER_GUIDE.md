# Obtainium Developer Guide

Obtainium is a Flutter (Android-first) app that installs and updates Android apps
**directly from their release sources** (GitHub, GitLab, F-Droid repos, HTML pages,
APK hosts, etc.). It scrapes/queries each source for the latest release, downloads
the APK (or split-APK container / archive), and installs it — optionally silently
in the background.

This guide explains the architecture, the major subsystems, and the conventions you
should follow when working in this codebase.

---

## 1. Tech stack & entry points

| Concern | Choice |
| --- | --- |
| UI | Flutter, **Material 3 "Expressive"** (`useMaterial3: true`) |
| State management | `provider` (`ChangeNotifier`) |
| Persistence | One JSON file per app on disk + `SharedPreferences` for settings + `flutter_secure_storage` for credentials + `sqflite` for logs |
| Localization | `easy_localization` (`assets/translations/*.json`, key-based `tr()` / `plural()`) |
| Background work | `workmanager` (periodic background tasks, Android-only) |
| Installation | Installer abstraction (`StockInstaller` / `ShizukuInstaller` / `ExternalInstaller`) backed by `android_package_installer`, `shizuku_apk_installer`, `android_intent_plus` |

### Entry point: `lib/main.dart`

- `main()` bootstraps: `PlatformDispatcher.onError` handler (catches unhandled platform
  errors and logs them), trusted certs, date formatting, `EasyLocalization`, edge-to-edge
  system UI (SDK ≥ 29), notifications, then `runApp` inside a `MultiProvider`.
- A custom `ErrorWidget.builder` is installed so that rendering crashes show a
  user-friendly "close" screen rather than the default Flutter red screen.
- Providers are created in `main()` (not inside the widget tree) so background tasks
  can use the same instances: `AppsProvider`, `SettingsProvider`, `NotificationsProvider`,
  `LogsProvider`, `SourceProvider`. Read them everywhere via `context.read/watch/select`.
- `buildObtainiumTheme()` builds the app-wide Material 3 Expressive `ThemeData` once;
  **all shape/motion character lives here** (squircle `RoundedSuperellipseBorder`
  cards/dialogs, `StadiumBorder` pill buttons, emphasized page transitions, Material 3
  expressive sliders/progress indicators). Do not re-style these per widget — extend the theme.
- `_ObtainiumState` runs **side effects in `initState` (post-frame), not in `build()`**:
  permission requests, WorkManager scheduling (`_scheduleWorkManager`),
  first-run handling (`_handleFirstRun`), and the launch-by-notification check. Each is
  guarded so it runs once; a `SettingsProvider` listener re-runs service/first-run logic
  on settings changes. **Follow this pattern — never trigger navigation, dialogs, or
  service starts directly from `build()`.**
- `callbackDispatcher()` (annotated with `@pragma('vm:entry-point')`) is the headless
  WorkManager entry point registered via `Workmanager().initialize()`. It catches crashes,
  logs them, and calls `bgUpdateCheck()` to perform the actual background work.

There is also `main_fdroid.dart` for the F-Droid build flavour (sets `isFdroidBuild = true`).

---

## 2. Directory layout

```
lib/
├─ main.dart                      App bootstrap, WorkManager scheduling
├─ main_fdroid.dart               F-Droid flavour entry point
├─ theme.dart                     Material 3 Expressive ThemeData builder, shapes + motion tokens
├─ custom_errors.dart             ObtainiumError + typed errors with codes/stacks/data
├─ pages/                         Full screens (each is a StatefulWidget in a single file)
│  ├─ home.dart
│  ├─ apps.dart
│  ├─ app.dart
│  ├─ add_app.dart
│  ├─ settings.dart
│  └─ import_export.dart
├─ components/                    All UI: design tokens, form engine, feature widgets, dialogs
│  ├─ generated_form_model.dart   Form data model (pure Dart)
│  ├─ generated_form_renderer.dart Form widget rendering (includes modal/dialog wrapper)
│  ├─ ui_widgets.dart             AppIcon, EmptyState, ConnectedCard, LinkText, CustomAppBar, showMessage/showError, positional tile helpers
│  ├─ settings_widgets.dart       SettingsGroup, SettingsTile, etc.
│  ├─ app_list_tile.dart          AppListTile, AppListBuilder, changelog helpers
│  ├─ app_detail_widgets.dart     AppInfoDialog, AppFilePicker
│  └─ category_editor.dart        Category management UI
├─ providers/                     State, business logic, services, models
│  ├─ apps_provider.dart          Core AppsProvider + download primitives + TranslationLoader + NativeFeatures
│  ├─ apps_provider_*.dart        Lifecycle, updates, install, import/export extensions
│  ├─ source_provider.dart        Immutable App model + TypedSettings + AppSource + SourceProvider + HttpService + VersionService + legacy JSON migrations
│  ├─ settings_provider.dart      Typed getters/setters over SharedPreferences
│  ├─ logs_provider.dart          sqflite-backed logs + Logger/AppLogger
│  ├─ notifications_provider.dart Local notifications
│  └─ external_install_bridge.dart External installer discovery + content-URI conversion
├─ installers/                    Install strategy abstraction
│  ├─ installer.dart              Abstract Installer + InstallResult
│  ├─ stock_installer.dart        AndroidPackageInstaller
│  ├─ shizuku_installer.dart      Shizuku/Dhizuku/Sui
│  └─ external_installer.dart     Third-party installer hand-off
└─ app_sources/                  One file per supported source (28 sources + githubstars)
```

---

## 3. State management & data model

### Providers
State lives in `ChangeNotifier` providers exposed through `provider`. **Read providers
narrowly** to avoid rebuild amplification:

- `context.read<T>()` — one-off access (event handlers, `initState`).
- `context.select<T, R>((p) => p.field)` — rebuild **only** when `field` changes.
- `context.watch<T>()` — rebuild on **any** change. Avoid for big providers like
  `AppsProvider`; prefer `select`. (Several perf fixes in this codebase were exactly
  "replace `watch` with `select`".)

### The `App` model (`source_provider.dart`)

`App` is the persisted unit. Key fields: `id` (Android package id or a temp hash),
`url`, `author`, `name`, `installedVersion`, `latestVersion`, `apkUrls`
(`List<MapEntry<name, url>>`), `preferredApkIndex`, `additionalSettings`
(`Map<String, dynamic>` — per-app source options), `categories`, `pinned`,
`overrideSource`, `pendingRepoRenameUrl`, and `allowIdChange`.

- `App.toJson()` / `App.fromJson()` serialize to/from disk.
- `App.fromJson()` runs **`appJSONCompatibilityModifiers()`** — a chain of idempotent
  schema migrations (legacy → current). Every migration is written to be safe to re-run
  on already-migrated data, so they simply run on every load. It is wrapped in try/catch
  so a single bad migration can't brick loading. Default-setting reconciliation always runs
  regardless.
- `App` is **immutable** — use `App.copyWith(...)` to create a modified copy instead of
  mutating fields directly.

### `AppInMemory` (`apps_provider.dart`)

Runtime wrapper around `App` that also holds a `DownloadState` (which wraps `downloadProgress`
as a `ValueNotifier` for efficient per-tile updates — shared by reference so UI listeners
survive `saveApps` copy-and-replace), `installedInfo` (`PackageInfo` from the OS), the
cached `icon` bytes, and a `sourceType` field for tracking which source produced the app.
`AppsProvider.apps` is a `Map<String, AppInMemory>` kept in sync with disk.

### Persistence rules (`apps_provider_lifecycle.dart`)

- Each app is a JSON file in `app_data/<id>.json`. Writes go to `<id>.json.tmp` then
  `renameSync` — **atomic write**, never partially-written files (#2089).
- Corrupt JSON on load is renamed to `*.corrupt` and skipped, not fatal.
- `loadApps()` is serialized via a `Completer` lock (`waitForAppsToLoad()`), not a
  busy-wait. It batches all parsing then notifies once.
- `saveApps()` reconciles install status (unless `attemptToCorrectInstallStatus: false`),
  updates in-memory state, notifies once, and schedules a debounced auto-export.
- Icons are cached as PNG in an `icons/` cache dir and deleted when an app is uninstalled.

---

## 4. The Source system (the core extensibility model)

This is the heart of Obtainium. **To add support for a new app source, add one file in
`lib/app_sources/` and register it in `SourceProvider._buildSources()`.**

### `AppSource` (abstract, in `source_provider.dart`)

A source is a subclass of `AppSource`. The base class is effectively **immutable after
construction** (all config is set in the subclass constructor body — a few sources
override `name` after `super()`), which is why instances can be cached and shared.

Configure behaviour by setting fields in the constructor:

```dart
class MySource extends AppSource {
  MySource() {
    hosts = ['example.com'];          // domains this source matches
    name = 'MySource';                // set automatically in super() as runtimeType, can be overridden
    canSearch = true;                 // supports search()
    appIdInferIsOptional = true;
    showReleaseDateAsVersionToggle = true;
    allowIncludeZips = true;
    allowIncludeTarballs = true;
    // Per-app options shown in the add/edit form:
    additionalSourceAppSpecificSettingFormItems = [ [GeneratedFormSwitch(...)], ... ];
    // Source-wide options stored in SettingsProvider (e.g. an API token):
    sourceConfigSettingFormItems = [ GeneratedFormTextField('example-creds', ...) ];
  }
}
```

Override the contract methods you need:

| Method | Responsibility |
| --- | --- |
| `sourceSpecificStandardizeURL(url, {forSelection})` | Validate + normalize a URL to a canonical form, or throw `InvalidURLError`. Used for both selection and storage. |
| `getLatestAPKDetails(standardUrl, additionalSettings)` | **The main job:** fetch the latest release and return `APKDetails(version, apkUrls, names, releaseDate, changeLog, allAssetUrls)`. |
| `tryInferringAppId(standardUrl, {...})` | Best-effort detect the Android package id (optional). |
| `search(query, {querySettings})` | Return `{url: [name, description]}` (only if `canSearch`). |
| `getRequestHeaders(...)` | Provide auth/format headers (defined on `AppSource`). |
| `getSourceNote()` | Markdown note shown in the UI (e.g. "add a token to avoid rate limits"). |
| `changeLogPageFromStandardUrl(url)` | URL of the human-readable changelog/releases page. Set `changeLogPageIsStandardUrl = true` in the constructor instead of overriding this if the changelog page is the same as the standard URL. |
| `postProcessApp(app)` | Transform the `App` object after all other processing (e.g. F-Droid repos update the URL with an `appId` query param). |

### Helpers you should reuse (don't reinvent)

- **`standardizeUrlWithRegex(url, subdomainPrefix:, pathPattern:)`** — the common
  "regex against host + path, return match or throw `InvalidURLError`" pattern. Most
  sources should adopt this helper rather than inlining their own regex construction.
- **`AppSource.isApkOrContainerFile(name, {includeArchives, includeTarballs})`** — the
  **single source of truth** for "is this file an installable container?". Recognizes
  `.apk/.xapk/.apkm/.apks` (+ optional `.zip` and tarballs). Use it instead of
  hand-rolling `.endsWith('.apk')`, which historically missed split-APK formats.
- `sourceRequest(...)` — the base HTTP method. It merges source config + per-app
  settings, applies header/prefetch modifiers, follows redirects with a cap, and
  always closes the `HttpClient`. **Use this**, not a raw `http.get`.
- `filterApks`, `filterApksByArch`, `extractVersion`, `findStandardFormatsForVersion`,
  `getLinksFromParsedHTML`, `getApkUrlsFromUrls`.

### `SourceProvider` (the service)

- **Singleton** (`factory SourceProvider() => _instance`). All `SourceProvider()` calls
  return the same object.
- `sources` is a **cached, shared, read-only** list built lazily by `_buildSources()`.
  Because sources are immutable, this is safe. **The only mutating path** is
  `getSource(url, overrideSource: ...)`, which builds a *throwaway* fresh instance so the
  cache stays pristine.
- `getSource(url)`: first tries host-regex matching against sources with `hosts`, then
  falls back to host-less sources via `sourceSpecificStandardizeURL` — **`HTML()` is
  always last** as the catch-all. Match errors are logged, never swallowed silently.
- `getApp(...)`: orchestrates `getLatestAPKDetails` → version extraction → APK filtering
  → arch filtering → builds the final `App`. This is where `versionExtractionRegEx`,
  `releaseDateAsVersion`, `apkFilterRegEx`, `autoApkFilterByArch`, app-id inference, and
  `overrideSource` are all applied.

---

## 5. UI layer & component conventions

### Navigation shell (`pages/home.dart`)

`HomePage` is an **adaptive** shell:
- **Bottom `NavigationBar`** on compact screens, **`NavigationRail`** on wide
  (`width >= 600`) / TV layouts.
- **Two-pane** list+detail on very wide screens (`width >= 900`) for the Apps tab.
- Single-pane content on wide screens is **width-capped at 720px** and centered.
- Update count is shown as a live `Badge` driven by
  `context.select<AppsProvider>(...findAppIdsWithPendingUpdates...)`.
- Only **two tabs** (Apps, Settings). "Add App" is a FAB; Import/Export are folded into
  the Add App page and Settings respectively.

### Deeplink routing (`pages/home.dart`)

`interpretLink(Uri uri)` (line 229) is the single deeplink dispatcher. It parses the
URI host as the **action** and dispatches accordingly:

| Action (`uri.host`) | Data source | Behaviour |
| --- | --- | --- |
| `add` | `uri.queryParameters['url']` or `uri.path.substring(1)` | Standardizes the URL, checks for duplicates, navigates to Add App page |
| `app` / `apps` | URI-decoded query or path | Shows a confirmation dialog with the raw JSON, then imports via `AppsProvider` |

Inbound links arrive via `AppLinks` (Android App Links / intent filters) — the
`obtainium://` scheme is registered in `AndroidManifest.xml`. Both `getInitialLink()`
(cold start) and `uriLinkStream` (warm start) feed into `interpretLink`, with a
dedup guard so the initial link isn't processed twice.

The **share sheet** (`ACTION_SEND` intent) added in the `MainActivity.kt` native layer
rewrites shared URLs as `obtainium://add/<url>` before they reach `interpretLink`, so
the same Dart-side dispatch handles both manual deeplinks and share-target intents.

### Reusable components (`lib/components/`)

Prefer these over bespoke widgets:

- **`theme.dart`** — `positionalTileShape({isFirst, isLast})`, `StadiumBorder`,
  `ExpressiveMotion.{emphasized, short, medium}` motion tokens. All shape and motion
  characters are defined here.
- **`ui_widgets.dart`** —
  - `AppIcon` (squircle icon with Obtainium glyph fallback, excluded from semantics),
  - `ActionListTile` (icon + label ListTile with optional auto-pop),
  - `ConnectedCard` (single tonal card; `isFirst`/`isLast` round outer corners so runs
    read as one block),
  - `EmptyState` (centered icon + caption for empty/loading/no-results),
  - `LinkText` (tappable external link, `Semantics(link: true)`),
  - `HighlightableButton` (FilledButton when "highlight touch targets" is on, else
    TextButton),
  - `CustomAppBar` (wrapping `SliverAppBar.large`),
  - `copyToClipboard(context, text)`, `showConfirmDialog(...) -> Future<bool>`,
    `showHelpDialog(context, title, content)`,
  - `showMessage(dynamic e, BuildContext, {bool isError})` — logs via `LogsProvider`
    and shows a snackbar (informational) or dialog (unexpected errors).
  - `showError(dynamic e, BuildContext)` — convenience wrapper around `showMessage`
    with `isError: true`.
- **`settings_widgets.dart`** — `SettingsGroup`, `SettingsSectionHeader`, `SettingsTile`,
  `SettingsToggleRow`, and `shapeSettingsTiles()` which auto-connects consecutive tiles.
- **`generated_form_renderer.dart`** — `GeneratedForm` widget (renders form items) and
  `GeneratedFormModal` (a `GeneratedForm` inside an `AlertDialog`; the standard way
  to ask the user for structured input or confirmation).
- **`app_list_tile.dart`** — `AppListTile` (the app row: swipe-to-install/remove,
  category gradient, pin/select states, download progress), `AppIconWidget`,
  `DownloadProgressTrailing`, and changelog dialog helpers
  (`showChangeLogDialog`, `getChangeLogFn`).
- **`app_detail_widgets.dart`** — `AppInfoDialog` (read-only app summary: icon, name,
  author, URL, version, last-check), `AppFilePicker` (choose among multiple APK/asset URLs),
  `APKOriginWarningDialog` (with "don't show again").
- **`category_editor.dart`** — `showCategoryEditor()`, `CategorySelector`,
  `CategoryManager`.

The `LogsPage` widget lives in `pages/settings.dart` since it's only used from the
settings page.

### The form engine (`generated_form_model.dart`)

Forms throughout the app (per-app settings, source config, search filters, confirm
dialogs) are **data-driven**. You describe fields as `List<List<GeneratedFormItem>>`
(rows of fields) and `GeneratedForm` (in `generated_form_renderer.dart`) renders + validates
them:

- `GeneratedFormTextField` (with optional autocomplete, password, multi-line,
  validators, help URL/dialog)
- `GeneratedFormSwitch` (bool; supports `disabled`)
- `GeneratedFormDropdown` (`opts`, `disabledOptKeys`)
- `GeneratedFormSubForm` (nested repeatable groups, e.g. HTML intermediate links)

It reports changes via `onValueChanges(values, valid, isBuilding)`. Each
`GeneratedFormItem` has `ensureType()` (coerce stored value) and `clone()` (deep copy).
**Form items owned by a source are cloned (`cloneFormItems`) before defaults are
pre-filled**, because sources are cached/shared and in-place mutation would leak across
apps. `tileMode: true` renders fields in the connected-tile settings aesthetic.

---

## 6. Background updates & installation

### Background task architecture

Background work is scheduled via **`workmanager`** (Android periodic tasks). The flow:

1. `_scheduleWorkManager()` (in `lib/main.dart`) registers a periodic task (`obtainiumBgUpdateCheck`)
   with a 15-minute minimum interval, requiring network connectivity.
2. When triggered, Android invokes **`callbackDispatcher()`** (`lib/main.dart:64`), a top-level
   function annotated `@pragma('vm:entry-point')` registered via `Workmanager().initialize()`.
   It sets up the bare minimum (flush bindings, localization) and delegates to `bgUpdateCheck()`.
3. **`bgUpdateCheck(taskId, params)`** (`lib/providers/apps_provider.dart:1090`) runs headless
   (no widget tree), loads apps/settings from disk, and performs the actual check.
4. On errors, `callbackDispatcher` catches the exception, logs it, and returns `false` so
   WorkManager knows the task failed.

### `bgUpdateCheck` behaviour

1. Loads translations manually (no `BuildContext` available).
2. Bails early on no network / restrictions (Wi-Fi-only, charging-only) / disabled settings.
3. **Update mode** (`toCheck` non-empty): checks updates, splits results into
   notify-only vs silently-installable, sends grouped notifications, and **schedules
   retries that actually `await` the retry delay** so rate-limited hosts aren't hammered.
4. **Install mode** (`toCheck` empty): downloads + silently installs pending updates;
   Obtainium itself is always moved to install **last**.
5. Publishes saves via a broadcast `StreamController<void>` so the foreground
   instance can detect background writes and reload automatically. Errors during
   background tasks are caught and logged rather than crashing the headless process.

### Update checking (`apps_provider_updates.dart`)

- **`fetchUpdate(appId)`** fetches new metadata **without saving**;
  **`checkUpdate(appId)`** fetches and saves.
- **`checkUpdates()`** processes app IDs in **bounded chunks (max 8 concurrent)** and
  persists each chunk with a **single `saveApps()`** call. This is the key fix for the
  pull-to-refresh UI freeze: it caps concurrent network/parse load and cuts rebuilds from
  O(N) to O(N/chunk).

### Installation (`apps_provider_install.dart`)

`AppsProviderInstall` extension handles the full pipeline:
- `downloadApp(...)` → file or `DownloadedDir` (xAPK/zip/tarball get extracted).
- Tarballs are extracted from supported compression formats (gzip, bzip2, xz) into
  split APK directories.
- `installApk` / `installApkDir` select the installer strategy (`StockInstaller`,
  `ShizukuInstaller`, or `ExternalInstaller`) based on user settings. See
  `lib/installers/`.
- `canInstallSilently(app)` decides whether a background silent install is allowed.
- `moveObbFile` uses **SAF (`shared_storage`) on Android 11+**, direct file access on
  older versions.
- `downloadAndInstallLatestApps(...)` is the orchestrator used by both UI and background.
- Installs require the foreground (`waitForUserToReturnToForeground`); the swipe-to-install
  tile stays locked from download start through install handoff.

### Installer abstraction (`lib/installers/`)

The installer layer provides a strategy-pattern abstraction over Android package
installation methods. The abstract `Installer` class (`installer.dart`) defines:

```dart
abstract class Installer {
  Future<InstallResult> installApk(App app, String path, ...);
  Future<InstallResult> installApkDir(App app, String dir, ...);
}
```

Three concrete implementations:

| Installer | Backend | Use case |
| --- | --- | --- |
| `StockInstaller` | `android_package_installer` plugin (PackageInstaller session API) | Standard installs; supports silent install via ADB-granted `INSTALL_PACKAGES` |
| `ShizukuInstaller` | `shizuku_apk_installer` plugin | Self-update of Obtainium itself, or when Shizuku/Dhizuku/Sui is available |
| `ExternalInstaller` | Native `MethodChannel` bridge (`external_install_bridge.dart` + `MainActivity.kt`) | Hands off to a third-party installer app chosen by the user; lists eligible targets via `listInstallTargets()` and converts file paths to `content://` URIs via `FileProvider` |

The selection logic (in `apps_provider_install.dart`) checks: self-update → `ShizukuInstaller`;
user has chosen an external installer → `ExternalInstaller`; otherwise → `StockInstaller`.

### Credentials

Source credentials (e.g. `github-creds`, `gitlab-creds`) are stored in
`flutter_secure_storage` (encrypted), with **automatic migration** from any plaintext
`SharedPreferences` values left over from older versions.

---

## 7. Conventions & patterns to follow

**State / lifecycle**
- Side effects go in `initState`/post-frame callbacks/listeners, **never in `build()`**.
- Prefer `context.select` over `context.watch` for large providers.
- Guard every `setState`/`Navigator`/`ScaffoldMessenger` call after an `await` with
  `if (!context.mounted) return;` (preferred over bare `mounted` in Flutter ≥ 3.7).
- Deep-copy an `App` before mutating (`App.copyWith(...)`); never mutate provider-owned
  objects in place.

**Errors / robustness**
- Throw `ObtainiumError` (or a typed subclass in `custom_errors.dart`) rather than raw
  `String`s. Key types: `RateLimitError` (with remaining minutes), `InvalidURLError`,
  `NoReleasesError`, `NoAPKError`, `NoVersionError`, `DowngradeError`, `InstallError`,
  `IDChangedError`, `RepositoryRenamedError`.
- In source files, wrap the main fetch logic:

  ```dart
  try {
    // ... fetch and parse ...
  } catch (e, stack) {
    rethrowOrWrapError(e, stack: stack);
  }
  ```

  `rethrowOrWrapError()` from `custom_errors.dart` passes through existing
  `ObtainiumError`s unchanged and wraps raw exceptions with a stack trace.
- In pages, use the helper functions:

  ```dart
  try {
    await appsProvider.downloadAndInstallLatestApps([appId]);
  } catch (e) {
    if (!context.mounted) return;
    showError(e, context);  // logs + shows dialog for unexpected errors
  }
  ```

- Errors use **deferred localization**: the code is set at construction time (e.g.
  `RateLimitError(5)`) but the user-facing message
  is resolved via `localizeErrorCode()` only when `message` is read. This lets errors
  be created in background tasks where no translation context is available.
- `MultiAppMultiError` bundles multiple per-app errors for batch operations; use
  `errors.add(appId, error, appName:)` to collect them.
- Never silently swallow exceptions. Log them via `LogsProvider().add(...)` or the
  `Logger`/`AppLogger` abstraction (preferred for structured logging: `logger.debug()`,
  `logger.info()`, `logger.warn()`, `logger.error()`).

**Categories & colour coding**
- Categories are stored as `Map<String, int>` (name → ARGB colour) in shared preferences.
- `generateRandomLightColor()` in `generated_form_renderer.dart` produces pastel colours using the
  HSLuv colour space with golden-angle hue distribution.
- `addMissingCategories()` in `apps_provider_lifecycle.dart` reconciles any categories
  found in stored apps but missing from the settings map.

**Resources**
- Always `close()` an `HttpClient`/`IOClient` (use `finally`). Dispose
  `TextEditingController`s, stream subscriptions, and timers.

**UI / a11y / i18n**
- Use the theme; don't hardcode colors/shapes. Pull colors from
  `Theme.of(context).colorScheme`.
- All user-facing strings go through `tr()` / `plural()` with a key in **every**
  `assets/translations/*.json` (at minimum `en.json`).
- Reuse `ConnectedCard`/`SettingsTile`/`positionalTileShape` for grouped tiles instead of
  hand-rolling `Material(shape: ...)`.

---

## 8. Building, running, testing

```bash
flutter pub get
flutter analyze        # must be clean
dart format --set-exit-if-changed .
flutter run            # default flavour
flutter build apk --flavor normal   # or use ./build.sh
```

- **Flavours:** `normal` (default, `lib/main.dart`) and `fdroid` (`lib/main_fdroid.dart`,
  reproducible-build friendly).
- Several dependencies are **git-pinned to commit SHAs** in `pubspec.yaml`
  (`android_package_installer`, `android_package_manager`, `shared_storage`,
  `shizuku_apk_installer`, `android_system_font`) — keep them pinned; don't
  switch to `ref: main`/`ref: master`.
- `sign.sh` reads the keystore password from an env var and locates `apksigner` robustly;
  `build.sh` / `docker/Dockerfile` handle reproducible/CI builds.
- **Note:** The project currently lacks automated tests. Run `flutter analyze` and
  `dart format --set-exit-if-changed .` locally before opening a PR.

---

## 9. Where to start for common tasks

| Task | Start here |
| --- | --- |
| Add a new app source | New file in `app_sources/`, register in `SourceProvider._buildSources()` |
| Add a per-app option | The source's `additionalSourceAppSpecificSettingFormItems` (or the base `_commonAppSettingFormItems` accessed via `combinedAppSpecificSettingFormItems`) |
| Add a global setting | A typed getter/setter in `settings_provider.dart` + a corresponding widget in `settings.dart` (e.g. `SettingsToggleRow`, `GeneratedFormDropdown`). Settings are organized into sections via `_buildUpdatesSection()` and `_buildAppearanceSection()` — add your control to the appropriate section. |
| Change update logic | `apps_provider_updates.dart` (foreground) / `bgUpdateCheck` (background) |
| Change install behaviour | `apps_provider_install.dart` |
| Add a reusable widget/dialog | `components/ui_widgets.dart` (or a dedicated component file) |
| Theme/shape/motion tweaks | `buildObtainiumTheme()` in `lib/theme.dart` (`positionalTileShape`, `StadiumBorder`, `ExpressiveMotion` tokens all live here) |
