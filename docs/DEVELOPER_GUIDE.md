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
| Installation | Installer abstraction (`StockInstaller` / `ShizukuInstaller` / `ExternalInstaller` / `RootInstaller`) backed by `android_package_installer`, `shizuku_apk_installer`, `android_intent_plus`, `su` |

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
│  ├─ document_tree_bridge.dart   Document-tree picker + Downloads exports (Android 10+, picker-less TVs)
│  └─ external_install_bridge.dart External installer discovery + content-URI conversion
├─ installers/                    Install strategy abstraction
│  ├─ installer.dart              Abstract Installer + InstallResult
│  ├─ stock_installer.dart        AndroidPackageInstaller
│  ├─ shizuku_installer.dart      Shizuku/Dhizuku/Sui
│  ├─ external_installer.dart     Third-party installer hand-off
│  └─ root_installer.dart         Root `su` + `pm install`
└─ app_sources/                  One file per supported source (29 sources + githubstars)
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
`disabled` (skips all update checks and background installs while keeping the
entry in the list, sorted to the bottom), `overrideSource`, `pendingRepoRenameUrl`, and `allowIdChange`.

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
| `getLatestAPKDetails(standardUrl, additionalSettings)` | **The main job:** fetch the latest release and return `APKDetails(version, apkUrls, names, releaseDate, changeLog, releaseUrl, appId, apkSizeBytes)`. |
| `getLatestAPKDetailsWithContext(standardUrl, additionalSettings, {currentApp})` | Update-check entry point (the base class delegates to `getLatestAPKDetails`). Override when the previous app matters, e.g. to skip scraping when the release is unchanged (APKMirror). |
| `prefetchUpdateInfo(apps)` | Optional pre-pass before a batch of checks. Override to fetch shared data once (APKMirror batches its API lookup into 1 request per 100 apps). |
| `tryInferringAppId(standardUrl, {...})` | Best-effort detect the Android package id (optional). Can be skipped by returning an id via `APKDetails.appId`. |
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
  always closes the `HttpClient`. **Use this**, not a raw `http.get`. Sources can opt
  into a per-host request gate (`enableHostRequestGate`, `maxConcurrentRequestsPerHost`)
  that bounds metadata concurrency and short-circuits a host for a window after a
  `429`/`503`/Cloudflare challenge (APKMirror uses 2 concurrent).
- `filterApks`, `filterApksByArch`, `extractVersion`, `findStandardFormatsForVersion`,
  `getLinksFromParsedHTML`, `getApkUrlsFromUrls`.

### Samsung Galaxy Store settings

Galaxy Store exposes per-app device model (`deviceId`) and CSC (`csc`) settings.
Empty fields retain the defaults `SM-S948B` and `DBT`. CSC `CHC` automatically
selects mobile country code `460` and mobile network code `00`; other CSCs retain
the existing `425` and `01` defaults. CHC matching ignores case and surrounding
whitespace. App configs that carry nonempty `mcc` and `mnc` values (for example
via an imported settings file) still override these defaults independently. They
remain strings to preserve leading zeros.

For example, Samsung Assistant (`com.samsung.android.app.sreminder`) can be
queried with device model `SM-S9480` and CSC `CHC` for the China release.
Availability still depends on the requested app, device, and Android SDK version.

After a failed stub request, ODS uses the same configured device and network
parameters. `CHC` with MCC `460` selects the China service; other configurations
use the global service. `countrySearchEx` (`2300`) discovers the endpoint without
changing MCC, MNC, or CSC. Only known Samsung ODS hosts and `/ods.as` are accepted;
trusted HTTP endpoints are upgraded to HTTPS. This preserves the existing
`425`/`01` global profile through the observed `il-odc.samsungapps.com` endpoint.
Discovery failure uses a fixed China or global endpoint with the original
request parameters.

ODS queries `getDownloadInfo` (`2298`). Native products then obtain a full APK
through `downloadEx2` (`2311`). This stateless request omits the installed
`versionCode` and uses the protocol spelling `dowloadType=new`. Only HTTP 400–599 responses
that are not rate limits or a valid nonzero API rejection may retry
`downloadForRestore` (`2316`). If both reject a
China request with a known full-package size, `downloadInfoForTencent` (`2801`)
is attempted once. Its result must identify the exact package, product, version,
version code, and full size and use a Samsung HTTPS APK URL. Partial or third-party
mirror responses fail; no purchase or order requests are made. A successful
anonymous `2801` response has not been demonstrated for Samsung Assistant.

China linked products with `linkProductYn=1` and a known full-package size use
`downloadInfoForTencent` (`2801`) directly. Linked replies must match the selected
version, version code, and full size. They may omit `GUID` and `productID`, but
either field must match when present; their `appId` is a Tencent catalog ID,
not an Android package name. Only this branch additionally permits the exact
HTTPS APK host `auto-dd.myapp.com`. Stub, native, restore, and nonlinked mirror
responses retain the Samsung-only host restriction. Unknown linked flags,
linked products outside China, or linked products without a full size fail
before authorization. No purchase or order request is made.

Stub and ODS responses reject malformed XML, duplicate critical fields,
incorrect identities, mismatched grants, and unsafe APK URLs. ODS response IDs
must match the requested interface. Login-required or non-installable metadata
fails before authorization. Full APKs, including universal `32n64` packages, are
accepted; delta URLs are unused. ODS POST redirects are disabled and headers do
not affect APK transfers.

Optional store dates and publisher notes use same-endpoint main (`2290`),
overview (`2291`), and main (`2290`) requests. Both main responses must match the
selected package, product, version, version code, and full size; overview must
match its version and size. This binds overview fields that omit package and
version code. Structured display branches are ignored while critical fields
remain unique scalar values. The validated overview `lastUpdateDate` populates
`releaseDate`; APK filename timestamps are not release dates. Publisher
`updateDescription` populates `changeLog` without rewriting its text. Missing,
changed, malformed, or unavailable details leave these fields unset and preserve
the authorized APK.

The source remains per-app: it does not add cross-app update batches or new
settings. Anonymous ODS requests reuse one generated identity throughout the
operation and do not require account credentials. Stub and ODS requests have
40-second deadlines. A stub timeout can use the same-profile ODS fallback;
ODS timeouts do not trigger restore or mirror authorization. Rate limits retain
their retry timing and stop the fallback chain. During optional discovery or
store details, a rate limit preserves the already authorized APK and stops
further detail requests.

### Source-specific notes: F-Droid page metadata

The F-Droid API does not expose per-APK ABIs or release dates. For the official
host (and an explicit override of it), `FDroid` reads the `/en/packages/<id>/`
page once per check, cached in memory for ten minutes, and uses:

- `package-nativecode` to filter builds by the device ABI and to label rows in
  the APK picker (`getApkAbisByUrl`);
- `Added on <date>` to populate `releaseDate`, including when the app has only
  one APK.

Page failures are non-fatal: the source keeps the API selection and leaves the
date/ABI labels unset. Custom F-Droid-compatible hosts are not scraped; the
existing `FDroidRepo` index metadata remains the source of truth there.

### Source-specific notes: HTML release dates

HTML release-date extraction runs the configured regex against the selected
APK link's own HTML block first (anchor, then up to three ancestors). This keeps
pages that list one “Last modified” date per APK from returning another build's
date. If the selected block has no match, it falls back to the whole-page string
used by version extraction. Parsing is English (`en_US`) with ordinal/AM-PM
normalization and a `DateTime.tryParse` fallback; direct APK links have no page
and therefore no scraped date.

### Source-specific notes: APKMirror

APKMirror is track-only and keeps regular-page traffic to a minimum:

- **Update checks** use the batched `app_exists` API (`1 request per ≤100 apps`)
  via `prefetchUpdateInfo`/`getLatestAPKDetailsWithContext`. The API credential is
  APKUpdater's shared key (`APKMirror._apiBasicAuth`); swap the constant when
  APKMirror issues Obtainium its own. Failures set an API cooldown and surface as
  `RateLimitError` — there is intentionally no feed fallback on API failure.
- **Feed fallbacks** cover apps whose id is a temporary placeholder (hash-only
  icon filename) and listings whose returned `app.link` does not match the tracked
  listing (packages can map to several listings, e.g. Spotify phone/Wear/Automotive).
- **Scraping** (release page → size, changelog when the API's `whats_new` is empty)
  happens once per *new release* only, during the check, and the result is persisted
  on `App.apkSizeBytes`. It is skipped when the stored `releaseUrl` is unchanged and
  when the release is too young for the minimum update age.
- Package ids are inferred from the feed icon filename at add time; the feed is the
  only non-API source that is listing-scoped. Temp-ID apps stay on the feed.

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
- `buildPlaceholderApp(...)`: builds a not-yet-checked entry (URL as name, source as
  author, temp ID, `placeholder` APK URLs). Used by the add flow when the setting
  `allowAddingAppsWithoutCheck` is on and the check fails unexpectedly; the next
  successful check fills it in and the real package ID is adopted on first install.

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

Flutter's built-in route-based deeplinking is disabled
(`flutter_deeplinking_enabled=false` in `AndroidManifest.xml`). The engine
default is enabled, which pushed every `obtainium://` intent to the Navigator
as a route with no matching handler and logged an `onUnknownRoute` error
alongside this dispatcher.

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
- `GeneratedFormHeader` (non-input section label; an optional `id` lets callers
  scroll a form to that section with `GlobalObjectKey`)

It reports changes via `onValueChanges(values, valid, isBuilding)`. Each
`GeneratedFormItem` has `ensureType()` (coerce stored value) and `clone()` (deep copy).
**Form items owned by a source are cloned (`cloneFormItems`) before defaults are
pre-filled**, because sources are cached/shared and in-place mutation would leak across
apps. `tileMode: true` renders fields in the connected-tile settings aesthetic, with
tile corners restarting after each header. `AppSource.combinedAppSpecificSettingFormItems`
groups the per-app dialog (and add-app form) into sections: the source's own section(s),
*Version detection*, *APK selection*, *Update options*, *App options*, and
*Update health detection* (see the update-health section above).

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
2. Bails early on no network / disabled settings, then evaluates the per-condition
   background guards (`bgGuardOnWiFi`, `bgGuardWhileCharging`, tri-state
   nothing/checksOnly/checksAndUpdates via `evaluateBgGuards`). `nothing` under an
   unmet condition aborts the task entirely; `checksOnly` allows checks and
   notifications but suppresses installs. The manual "Run background update check
   now" (`forceAll`) bypasses the "do nothing" guard for checks but only checks —
   it never installs, since the guards alone decide installs.
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
- Disabled apps and apps in a category listed in
  `categoriesExcludedFromChecks` are skipped by automatic checks (and disabled
  apps by background installs); `fetchUpdate` returns early for them.
- **`checkUpdates()`** first calls `AppSource.prefetchUpdateInfo` for each source
  present in the batch (APKMirror uses this to fetch up to 100 apps in one API
  request), then processes app IDs in **bounded chunks (max 4 concurrent)** and
  persists each chunk with a **single `saveApps()`** call. This is the key fix for the
  pull-to-refresh UI freeze: it caps concurrent network/parse load and cuts rebuilds from
  O(N) to O(N/chunk).

### Update health detection (`utils/update_health.dart`)

Apps that will likely never receive an update are flagged by evaluating local
signals; there is no separate scheduled job:

- General: `App.releaseDate` age, `App.latestVersionChangedAt` age (set when a
  check finds a new version), and `App.consecutiveFailedChecks` (incremented in
  `checkUpdates` for non-transient failures only, reset by any successful fetch).
- Source-specific: `App.isArchived` (GitHub fetches the repo JSON when the
  heuristic is enabled for the app, reusing the repo-rename response when
  available; GitLab reads it from the project call it already makes) and
  `App.newerReleasesFilteredOut` (counted inside GitHub's release selection).

`resolveUpdateHealthConfig` merges the global `SettingsProvider` values with the
per-app overrides in `additionalSettings` (`''` = use global, `'off'` =
disabled, a number = threshold). `evaluateUpdateHealthReasons` is a pure
function, so the settings page (`pages/update_health.dart`), the app list
indicator and the app detail link all reflect setting changes immediately.
`hasUpdateHealthIssues` additionally excludes disabled apps, apps pending a repo
rename, and ignored apps. The two opt-outs live on `App`:
`updateHealthEnabled` (permanent) and `updateHealthDismissedVersion` (ignored
while it equals `latestVersion`).

### Installation (`apps_provider_install.dart`)

`AppsProviderInstall` extension handles the full pipeline:
- `downloadApp(...)` → file or `DownloadedDir` (xAPK/zip/tarball get extracted).
- Tarballs are extracted from supported compression formats (gzip, bzip2, xz) into
  split APK directories.
- `installApk` / `installApkDir` select the installer strategy (`StockInstaller`,
  `ShizukuInstaller`, `ExternalInstaller`, or `RootInstaller`) based on user
  settings. See `lib/installers/`.
- `canInstallSilently(app)` decides whether a background silent install is allowed.
- `moveObbFile` uses **SAF (`shared_storage`) on Android 11+**, direct file access on
  older versions.
- `downloadAndInstallLatestApps(...)` is the orchestrator used by both UI and background.
- Installs require the foreground (`waitForUserToReturnToForeground`); the swipe-to-install
  tile stays locked from download start through install handoff.
- `downloadFileWithRetry` retries transient network errors (3 attempts, 5 s apart). Android
  blocks network access for backgrounded apps, so foreground downloads pass
  `holdRetry: _holdRetryUntilForeground`, which holds the retry until the app is back in the
  foreground (#2894) instead of spending the attempts offline. Callers that allow reusing
  partial files (`useExisting`) then resume from where the download stopped. The hook returns
  false — reporting the original error rather than retrying — when the app does not come back
  within `_backgroundRetryWait`; a cancellation while waiting surfaces as a
  `CancellationException` instead, so no error is shown for a download the user stopped.

### Installer abstraction (`lib/installers/`)

The installer layer provides a strategy-pattern abstraction over Android package
installation methods. The abstract `Installer` class (`installer.dart`) defines:

```dart
abstract class Installer {
  String get modeKey;
  Future<bool> canInstallSilently(App app);
  Future<bool> checkPermission();
  Future<void> ensurePermission();
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions,
  });
}
```

Four concrete implementations:

| Installer | Backend | Use case |
| --- | --- | --- |
| `StockInstaller` | `android_package_installer` plugin (PackageInstaller session API) | Standard installs; supports silent install via ADB-granted `INSTALL_PACKAGES` |
| `ShizukuInstaller` | `shizuku_apk_installer` plugin | Self-update of Obtainium itself, or when Shizuku/Dhizuku/Sui is available |
| `ExternalInstaller` | Native `MethodChannel` bridge (`external_install_bridge.dart` + `MainActivity.kt`) | Hands off to a third-party installer app chosen by the user; lists eligible targets via `listInstallTargets()` and converts file paths to `content://` URIs via `FileProvider` |
| `RootInstaller` | `su` + `pm install` CLI | Elevated installs for the current foreground user, not just user 0 (needed under multi-user) |

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
- Layout tokens live in `lib/theme.dart`; use them instead of raw numbers:
  `AppSpacings` (2/4/8/12/16/24/32), `AppPaddings` (`page`, `cardInner`,
  `rowHorizontal`, `listOuter`, `sliderTile`, `sectionHeader`,
  `listSectionHeader`), `AppRadii` (`inline`/`xs`/`small`/`medium`/`fab`/
  `large`/`xlarge`), and `AppIconSizes`.
- Section labels use the `SectionHeader` widget (or `sectionHeaderTextStyle`):
  `titleMedium`, weight 600, `onSurface`, 24px above / 8px below.
- Rows and form fields use 16px horizontal content padding. Page content uses
  `AppPaddings.page`; full-bleed app lists use `AppPaddings.listOuter` and
  `AppListRowCard`; grouped settings use `ConnectedCard`/`CardTile` with
  `AppSpacings.connectedGap` between segments.
- Reuse `AppListTile`/`AppListRowCard` for app rows so list density, version
  labels and update-health indicators stay consistent.
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
- Run `flutter analyze` and `dart format --set-exit-if-changed .` locally before opening a PR.

### End-to-end tests (emulator)

The E2E suites live in `integration_test/` and drive the real app on an attached
emulator or device. Always use the runner: it generates the fixture APKs, starts
a local HTTP server on `:8000`, disables animation scales, installs the test
package with Obtainium as its installer (so silent updates are allowed), runs
each suite through `flutter test` on the device, and restores everything
afterwards.

```bash
./tool/e2e.sh              # auto-detect the attached device; run all applicable suites
./tool/e2e.sh --no-install # skip the install/update suite
./tool/e2e.sh --tv         # force the TV suites (auto-detected normally)
./tool/e2e.sh --help
```

- Requires a running emulator/device (launching it is left to you) and an
  Android SDK (`ANDROID_HOME`, defaulting to `~/Android/Sdk`) with build-tools
  and a platform JAR. Set `E2E_DEVICE=<serial>` when more than one device is
  attached.
- Phone/tablet suites: `smoke_test`, `add_remove_app_test`,
  `screens_navigation_test`, `install_update_test`. TV-only suites:
  `tv_navigation_test`, `tv_controls_test`, `tv_layout_test`.
- Fixture APKs are generated by `tool/e2e_assets.sh` into `build/e2e_assets/`
  and are never committed.
- Suites are device-guarded: TV suites skip on a phone and vice versa. Running a
  single file directly with
  `flutter test integration_test/<file>.dart -d <device> --flavor normal` is
  only for debugging; the install suite then needs
  `--dart-define=E2E_RUN_INSTALL=true` plus the runner's server and
  pre-install setup, and skips with an explanation otherwise.

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
| Add or change an end-to-end test | `integration_test/` suites; run them with `tool/e2e.sh` (see "End-to-end tests" above) |
