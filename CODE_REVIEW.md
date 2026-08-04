# Obtainium — Code Review and Refactoring Plan

**Scope:** `lib/` (≈24,400 lines of Dart across 49 files). No new features; focus on reducing complexity, improving readability/maintainability, architectural improvements, and bug fixes.

**Method:** Four parallel deep-dive reviews covering `app_sources/`, `providers/`, `pages/`, and `components/` + `installers/` + root `lib/` files. Findings below are consolidated, deduplicated, and prioritized. Every item includes a `file:line` reference so it can be acted on independently.

---

## Table of Contents

1. [Bugs (correctness, resource leaks, race conditions)](#1-bugs)
2. [Architectural / Design Recommendations](#2-architecture)
3. [Code Duplication](#3-duplication)
4. [Long / Complex Methods to Decompose](#4-long-methods)
5. [Dead Code to Remove](#5-dead-code)
6. [Hardcoded Values to Extract as Constants](#6-constants)
7. [State Management & Rebuild Efficiency](#7-state-management)
8. [UI / Widget Tree Decomposition](#8-ui-decomposition)
9. [Cross-Cutting Conventions to Standardize](#9-conventions)
10. [i18n / Accessibility](#10-i18n)
11. [Suggested Phased Execution Plan](#11-phased-plan)

---

## 1. Bugs

Bugs are ordered by severity. The first six are real correctness or resource-lifecycle issues; the rest are latent or edge-case.

### 1.1 [HIGH] `ReceivePort` leak in download-cancel listener

**File:** `lib/providers/notifications_provider.dart:321-338`

`listenForDownloadCancelFromMain` looks up any existing port by name and *removes the name mapping*, but **never closes the previous `ReceivePort`**. Native `ReceivePort`s are not GC'd until explicitly closed. Every re-registration (hot reload, tests, accidental double-init) leaks a port and its listener callback.

**Fix:** Track the port statically and close before re-registering:

```dart
static ReceivePort? _downloadCancelPort;

static void listenForDownloadCancelFromMain() {
  _downloadCancelPort?.close();
  _downloadCancelPort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    _downloadCancelPort!.sendPort, _downloadCancelPortName,
  );
  _downloadCancelPort!.listen(...);
}
```

### 1.2 [HIGH] `extractTarballFile` runs sync decode + sync writes on the UI isolate

**File:** `lib/providers/apps_provider_install.dart:430-471`

GZip/BZip2/XZ decode, TarDecoder decode, and per-file `writeAsBytesSync` are all synchronous and run on the main isolate. For large bundles (OBB-bearing games can be hundreds of MB) this freezes the UI and risks ANRs.

**Fix:** Move to `Isolate.run` / `compute`, or at minimum switch to async `writeAsBytes` and yield between files. The decompression is the dominant cost and must be off-isolate.

### 1.3 [HIGH] FDroidRepo caches mutable per-app state on a shared source instance

**File:** `lib/app_sources/fdroidrepo.dart:12,32,111-118`

`bool _appIdFoundInUrl = false` is mutated in `runOnAddAppInputChange`. But `SourceProvider` caches source instances in `_cachedSources` (`source_provider.dart:950-951`) and the base-class comment at `source_provider.dart:948-949` explicitly says sources are immutable after construction. If user A adds an F-Droid repo URL containing `?appId=foo`, `_appIdFoundInUrl` becomes `true`; when user B then adds a URL without `?appId`, the cached instance still reports `true` and the `appIdOrName` form field becomes `required: false` when it should be required.

**Fix:** Return the flag from `runOnAddAppInputChange` and store it on the calling page, not on the source.

### 1.4 [HIGH] GitHub release loop miscounts drafts in skip logic

**File:** `lib/app_sources/github.dart:522-531`

```dart
var prereleaseSkipped = 0;
for (int i = 0; i < releases.length; i++) {
  if (!fallbackToOlderReleases && i > prereleaseSkipped) break; // line 524
  if (!includePrereleases && releases[i]['prerelease'] == true) {
    prereleaseSkipped++; continue;
  }
  if (releases[i]['draft'] == true) {
    continue; // line 531 — skipped but NOT counted
  }
```

When `!fallbackToOlderReleases` and the first release (i=0) is a draft, it is skipped without incrementing `prereleaseSkipped`. At i=1, `i > prereleaseSkipped` (1 > 0) is true → early `break`. The next valid release is never examined.

**Fix:** Use a single `skipped` counter that counts both prereleases and drafts, or restructure the break condition to compare against total skipped (not just prereleases).

### 1.5 [MEDIUM] GitHub sort comparator violates symmetry for null dates

**File:** `lib/app_sources/github.dart:460,470`

```dart
return (dateA ?? DateTime(1)).compareTo(dateB ?? DateTime(0));
```

When both `dateA` and `dateB` are null the result is always `+1` regardless of argument order, violating `compare(a,b) == -compare(b,a)`. Sort is unstable for null-dated releases.

**Fix:** Use the same sentinel on both sides: `(dateA ?? DateTime(0)).compareTo(dateB ?? DateTime(0))`.

### 1.6 [MEDIUM] FDroidRepo `selectedReleases[0]` without empty check

**File:** `lib/app_sources/fdroidrepo.dart:283`

If the filter at lines 260-266 yields no matches, `selectedReleases` is empty and `selectedReleases[0]` throws `RangeError`.

**Fix:** `if (selectedReleases.isEmpty) throw NoReleasesError();` before line 283.

### 1.7 [MEDIUM] Double `rethrowOrWrapError` wraps and double-logs

**File:** `lib/app_sources/apkpure.dart:259-268`

The inner `rethrowOrWrapError(e)` at line 262 throws, but the outer `catch (e) { rethrowOrWrapError(e); }` at line 268 catches the already-wrapped error and wraps it again — and `rethrowOrWrapError` (`custom_errors.dart:91-97`) logs on each wrap, so unexpected errors are logged twice and double-wrapped in `UNEXPECTED`.

Same anti-pattern in `lib/app_sources/sourceforge.dart:93-106` where the outer `catch (e) { return null; }` swallows the inner rethrown error, making the inner wrap pointless.

**Fix:** Remove the inner `rethrowOrWrapError` calls and let errors propagate to the single outer handler. For SourceForge, only catch specific expected exceptions (`FormatException`, `NoVersionError`) — let network errors propagate.

### 1.8 [MEDIUM] Static `onDownloadCancelRequested` can invoke a disposed provider

**File:** `lib/providers/apps_provider.dart:982` (assignment) and `:924-931` (`cancelDownload`)

`NotificationsProvider.onDownloadCancelRequested = cancelDownload;` is set in the constructor. `cancelDownload` calls `notify()` → `notifyListeners()` on `this`. If the provider is disposed but the static still points to it, a notification tap throws "A ChangeNotifier was used after being disposed." Contrast with `scheduleAutoExport` at line 949 which *does* check `_disposed`.

**Fix:** Add `if (_disposed) return;` at the top of `cancelDownload`, and clear the static in `dispose()`.

### 1.9 [MEDIUM] `AppsProvider` directory getters throw before async init completes

**File:** `lib/providers/apps_provider.dart:871-887`

The constructor launches an unawaited async init block (lines 985-1029) and stores any failure in `initError`, but **there is no public `Future` callers can await**. Any code path that touches `apkDir` / `iconsCacheDir` / `cachedAppsDir` before init finishes throws `StateError`. `removeApps` (`apps_provider_lifecycle.dart:448`) and `downloadApp` (`apps_provider_install.dart:223`) both hit `apkDir`.

**Fix:** Expose `Future<void> ready;` backed by a `Completer` and have callers `await ready;` before touching the directory getters.

### 1.10 [MEDIUM] `SourceProvider.getSource` swallows all errors during auto-detection

**File:** `lib/providers/source_provider.dart:990-992` and `:1004-1006`

```dart
} catch (e) {
  // Ignore and try the next source.
}
```

Catches *every* `Exception`/`Error` (including `StackOverflowError`, `StateError`, `RangeError`). A bug in any source's `sourceSpecificStandardizeURL` is silently swallowed and the URL falls through to `HTML` or throws a misleading `UnsupportedURLError`.

**Fix:** Catch only `ObtainiumError` (or `InvalidURLError` specifically).

### 1.11 [MEDIUM] Optimistic `installedVersion = latestVersion` written before install confirmation

**File:** `lib/providers/apps_provider_install.dart:629` (and the general pattern at lines 119, 130, 159, 510, 657, 864)

Direct `apps[id]!.app = apps[id]!.app.copyWith(...)` mutations are followed by `await saveApps([...])` with no rollback if the save or the subsequent install fails. The `installedVersion = latestVersion` at line 629 (the `needsBGWorkaround` branch) is set *before* the install is confirmed; if the install later fails, `findAppIdsWithPendingUpdates` (`apps_provider_updates.dart:260-270`) will no longer report the app as pending because the in-memory version was prematurely bumped.

**Fix:** Centralize mutation through a single `_updateApp(String id, App Function(App) update)` that saves-and-notifies, and only set `installedVersion` after install confirmation.

### 1.12 [MEDIUM] `prevApp` never reset on `appId` change (two-pane broken auto-update)

**File:** `lib/pages/app.dart:57,1229-1237`

`prevApp` is set once and never cleared. When `widget.appId` changes in two-pane mode, `didUpdateWidget` (lines 124-136) handles `_pendingAppIdChange` but does **not** reset `prevApp = null`, so the auto-update-check will not run for the new app.

**Fix:** Add `prevApp = null;` in `didUpdateWidget` when `oldWidget.appId != widget.appId`.

### 1.13 [MEDIUM] `context.read` in `home.dart` `initState`

**File:** `lib/pages/home.dart:42-44`

`context.read<...>()` is called in `initState`. The other pages (`apps.dart:68-75`, `app.dart:112-121`, `add_app.dart:66-75`) correctly defer this to `didChangeDependencies` with a `_providersInitialized` guard. `home.dart` is inconsistent and fragile.

**Fix:** Move the three `context.read` calls to `didChangeDependencies` with the same guard pattern used elsewhere.

### 1.14 [MEDIUM] Side effects scheduled from `build()`

Three call sites schedule work from inside `build()`, which Flutter can invoke multiple times per frame:

- `lib/pages/apps.dart:1008,1018` — `addPostFrameCallback` for auto-refresh and selection pruning.
- `lib/pages/app.dart:1225` — `_maybeProbeDownloadSize(app)` starts an async HTTP call.
- `lib/pages/app.dart:1234` — `addPostFrameCallback` for auto-update-check.

**Fix:** Move the auto-refresh check and the download-size probe trigger into `didUpdateWidget` / a listener; gate the post-frame callbacks with a single boolean flag set outside `build()`.

### 1.15 [MEDIUM] Unlocalized user-visible string "(OS installed ...)"

**File:** `lib/pages/app.dart:864`

```dart
'${tr('pseudoVersionInUse')} (OS installed $realVersion)'
```

English interpolated into a localized template. **Real i18n bug.**

**Fix:** Add a new translation key `pseudoVersionInUseWithRealVersion` with an `{osVersion}` parameter.

### 1.16 [LOW] Empty `setState(() {})` with no `mounted` guard

**Files:** ~26 occurrences across all pages. The most concerning is `lib/pages/apps.dart:142-144`:

```dart
.whenComplete(() {
  setState(() {}); // no mounted check — can throw after dispose
});
```

Empty-setState is also an anti-pattern: it triggers a full rebuild without indicating what changed.

**Fix:** Add `if (mounted)` guards everywhere; replace empty bodies with explicit field assignments. For provider-driven data, prefer `context.select` / `ValueListenableBuilder`.

### 1.17 [LOW] `_fontLoaded` flag prevents font reload on toggle

**File:** `lib/main.dart:329-332`

Once `_fontLoaded` is `true`, the system font is never reloaded even if the user toggles `useSystemFont` off and back on.

**Fix:** Track the previous `useSystemFont` value and reload when transitioning `false → true`, or make the flag reactive.

### 1.18 [LOW] `Random().nextInt(9900)` notification ID collisions

**File:** `lib/providers/apps_provider.dart:1259-1263`

By the birthday paradox, ~118 simultaneous error notifications yield a >50% chance of collision, silently overwriting an existing notification.

**Fix:** Use `appId.hashCode` or a monotonic counter for deterministic, collision-free IDs.

### 1.19 [LOW] `downloadFile` headers probe doesn't drain the response body

**File:** `lib/providers/apps_provider.dart:423-461`

A full GET is issued just to read `Content-Length` / `Accept-Ranges`, then the body is abandoned and the client closed. On HTTP/1.1 keep-alive this leaves the response unconsumed and produces log noise.

**Fix:** `await headersResponse.drain<void>();` before `headersClient.close()`, or use `HEAD` when the server supports it.

### 1.20 [LOW] `reconcileVersionDifferences` force-unwrap safe only by step ordering

**File:** `lib/providers/apps_provider_lifecycle.dart:132-135`

`app.installedVersion!` is safe only because step 1 (lines 119-125) sets it before step 2 runs. Any reordering would introduce a null-dereference.

**Fix:** Add an explicit `app.installedVersion != null` to the step-2 guard, or pass `app.installedVersion ?? realInstalledVersion`.

### 1.21 [LOW] String `!=` version comparison yields false-positive pending updates

**File:** `lib/providers/apps_provider_updates.dart:260-270`

Lexical comparison: `"1.2" != "1.2.0"` is `true`, so an app whose installed and latest versions are semantically equal but lexically different will be perpetually reported as pending.

**Fix:** Use `VersionService`-based comparison (which already exists for normalization) instead of raw string inequality.

### 1.22 [LOW] `initValid: false` silently overridden by post-frame callback

**File:** `lib/components/generated_form_renderer.dart:377-380,197-208`

The post-frame `notifyFormChange(isBuilding: true)` reads `FormFieldState.isValid` which returns `true` for unvalidated fields (because `autovalidateMode` is `onUserInteraction`), so `valid` becomes `true` and overrides the caller's `initValid: false`. Currently masked because all callers pass `initValid: true`, but the default is misleading.

**Fix:** When `isBuilding == true`, preserve the caller's `initValid` instead of recomputing validity, or call `validate()` first.

### 1.23 [LOW] `webViewLoaded` flag never reset on appId change

**File:** `lib/pages/app.dart:189-193`

When `widget.appId` changes (two-pane), `didUpdateWidget` sets `_pendingAppIdChange = true` but `webViewLoaded` stays `true`, so `ensureWebViewController` will never call `loadRequest` for the new URL. Masked in practice by `ObjectKey(webController)` recreating the webview, but the logic is contradictory.

**Fix:** Reset `webViewLoaded = false` in `didUpdateWidget` when `oldWidget.appId != widget.appId`.

### 1.24 [LOW] `ErrorWidget.builder` has hardcoded English strings

**File:** `lib/main.dart:117,122` — "An unexpected error occurred." and "Close" not localized.

**Fix:** Move the `ErrorWidget.builder` assignment after `EasyLocalization.ensureInitialized()` and use `tr()`, or accept English-only and extract to named constants.

### 1.25 [LOW] `setAppLocale` side effect inside `MaterialApp.builder`

**File:** `lib/main.dart:354-355`

Mutates the global `_appCurrentLocale` during the build phase. Works because nothing reads the global to trigger rebuilds, but violates build purity.

**Fix:** Move to a locale-change listener.

### 1.26 [LOW] `LogsProvider()` construction triggers DB cleanup as a side effect

**File:** `lib/providers/logs_provider.dart:60-71`

Constructing `LogsProvider()` (which many call sites do ad-hoc: `source_provider.dart:223`, `settings_provider.dart:442`, etc.) triggers a one-shot 7-day DELETE. Surprising side effect for "I want to log a line."

**Fix:** Move the cleanup to explicit invocation during app init.

---

## 2. Architectural / Design Recommendations

### 2.1 [MAJOR] `AppsProvider` is a god class spanning 5 files and ~4,060 lines

**Files:**
- `lib/providers/apps_provider.dart` (1,469 lines, core + downloads + background)
- `lib/providers/apps_provider_install.dart` (1,354 lines)
- `lib/providers/apps_provider_lifecycle.dart` (548 lines)
- `lib/providers/apps_provider_updates.dart` (274 lines)
- `lib/providers/apps_provider_import_export.dart` (225 lines)

`AppsProvider` is responsible for **at least 13 distinct concerns**: in-memory app state, file downloading with resume/range support, partial-hash/ETag version fingerprinting, APK installation + tarball/zip/xapk extraction, OBB file placement + SAF permissions, version detection/reconciliation, persistence, import/export, background update orchestration (top-level functions!), foreground/background lifecycle tracking, cancellation token management, auto-export debouncing, and a cross-isolate save-notification bus.

The extension-split (`apps_provider.dart:35-43` re-exports the four `apps_provider_*.dart` files) was a good instinct but **does not actually reduce coupling**: every extension reaches into `AppsProvider`'s private `apps` map and mutates `apps[id]!.app` directly. The `notify()` wrapper at line 907-909 exists only because Dart extensions in separate files can't see `@protected` members.

Additionally, two unrelated classes are jammed into `apps_provider.dart`:
- `TranslationLoader` (`apps_provider.dart:1422-1448`) — locale bootstrapping, duplicates logic in `main.dart`.
- `NativeFeatures` (`apps_provider.dart:1451-1469`) — system font loading.

**Recommendation:** Extract these collaborator classes, each in its own file, composed by `AppsProvider`:

| New class | Owns | Source lines |
|---|---|---|
| `DownloadService` | `downloadFile`, `downloadFileWithRetry`, `checkPartialDownloadHash*`, `checkETagHeader`, `_waitForConcurrentDownload`, `getDownloadSize`, `formatBytes`, `formatDownloadSize`, `DownloadState`, `DownloadedApk`, `DownloadedDir`, `CancellationToken` | ~400 |
| `InstallService` | `installApk`, `installApkDir`, `extractTarballFile`, `unzipFile`, `moveObbFile`, `handleAPKIDChange`, installer-strategy selection, `_shareWithVerifiedApps` | ~800 |
| `VersionReconciler` | `getCorrectedInstallStatusAppIfPossible`, `reconcileVersionDifferences`, `isVersionDetectionPossible`, `_getNaiveStandardVersionDetection`, `_getRealInstalledVersion` | ~150 |
| `BackgroundUpdateOrchestrator` | `bgUpdateCheck`, `_bgRunUpdateCheck`, `_runBGInstallMode` (currently top-level functions at `apps_provider.dart:1067-1405`) | ~340 |
| `AppPersistence` | `loadApps`, `saveApps`, `removeApps`, `getAppsDir` | ~250 |
| `TranslationLoader` | move to `lib/util/translation_loader.dart` | ~30 |
| `NativeFeatures` | move to `lib/util/native_features.dart` | ~20 |

Resulting `AppsProvider` would shrink to ~300 lines of state coordination + ChangeNotifier wiring, and each collaborator would be independently testable.

### 2.2 [MAJOR] `AppSource` base class buried in the wrong file

**File:** `lib/providers/source_provider.dart:400-857`

`source_provider.dart` (1,875 lines) contains: `AppNames`, `APKDetails`, `App`, `AppSource`, `MassAppUrlSource`, `SourceProvider`, `HttpService`, `VersionService`, `ApkFilterService`, `TypedSettings`, `preStandardizeUrl`, `getSourceRegex`, 12 top-level delegation functions, and 300+ lines of JSON migration logic. This is a god-object.

**Recommendation:** Split into:
- `lib/app_sources/app_source.dart` — `AppSource` abstract class only (the natural location; currently there is no `app_source.dart` at all).
- `lib/models/app.dart` — `App`, `AppNames`, `APKDetails`, `TypedSettings`.
- `lib/services/http_service.dart` — `HttpService`.
- `lib/services/version_service.dart` — `VersionService`.
- `lib/services/apk_filter_service.dart` — `ApkFilterService`.
- `lib/providers/source_provider.dart` — `SourceProvider` only.
- `lib/providers/app_json_migration.dart` — migration logic.

### 2.3 [MAJOR] `APKDetails` and `AppNames` are mutable

**File:** `lib/providers/source_provider.dart:49-72`

Fields `version`, `apkUrls`, `changeLog` (on `APKDetails`) and `author`, `name` (on `AppNames`) are mutable. Mutated in:
- `source_provider.dart:1091-1092` (`apk.version = extractedVersion;`)
- `source_provider.dart:1099` (`apk.apkUrls = filterApks(...)`)
- `source_provider.dart:1108` (`apk.apkUrls = await filterApksByArch(...)`)
- `fdroid.dart:108,117,159`
- `gitlab.dart:261`

Meanwhile `App` already has a correct `copyWith` with sentinel pattern (lines 158-212).

**Recommendation:** Make `APKDetails` and `AppNames` immutable with `copyWith`. Replace mutations with `apk = apk.copyWith(version: extractedVersion)`.

### 2.4 [MAJOR] GitHub doubles as a base class for Codeberg and GitLab

**Files:**
- `lib/app_sources/codeberg.dart:7` — `final GitHub _gh = GitHub(hostChanged: true);`
- `lib/app_sources/gitlab.dart:15` — `final GitHub _gh = GitHub(hostChanged: true);`
- `lib/app_sources/izzyondroid.dart:7` — `final FDroid fd = FDroid();`
- `lib/app_sources/direct_apk_link.dart:11` — `final HTML html = HTML();`
- `lib/app_sources/fdroid.dart:7-8` — imports `GitHub` and `GitLab` for changelog URL detection.
- `lib/app_sources/githubstars.dart:21` — `final GitHub _gh = GitHub();`

`GitHub` has two responsibilities: being the GitHub source and being a "Git-hosting platform base." Methods like `fetchReleaseDetailsWithTagFallback`, `searchCommon`, `getAppNames`, and `rateLimitErrorCheck` are public solely because Codeberg/GitLab need them.

**Recommendation:** Extract a `GitHostingSource` intermediate base class (or mixin) containing the shared release-fetching, search, and naming logic. `GitHub`, `GitLab`, and `Codeberg` would all extend it.

### 2.5 [MAJOR] `HTML` class doubles as a utility library

**File:** `lib/app_sources/html.dart:13-216`

`html.dart` exports standalone utility functions:
- `compareAlphaNumeric` (line 13) — used by `github.dart:480,482,488`.
- `collectAllStringsFromJSONObject` (line 45).
- `getLinksInLines` (line 96).
- `grabLinksCommonFromRes` (line 107).
- `grabLinksCommon` (line 119) — used by `farsroid.dart:96`.

So `github.dart` imports `html.dart` just for `compareAlphaNumeric`, creating an odd dependency where GitHub depends on HTML.

**Recommendation:** Move these utilities to `lib/utils/html_parsing_utils.dart` and `lib/utils/string_compare.dart`.

### 2.6 [MAJOR] Twelve top-level delegation functions add indirection

**File:** `lib/providers/source_provider.dart:84-86,348-398,859-902`

Twelve free functions exist solely to delegate to `HttpService`, `VersionService`, or `ApkFilterService` instances:

```
ensureAbsoluteUrl, getApkUrlsFromUrls, filterApksByArch, getSourceRegex,
createHttpClient, sourceRequestStreamResponse, httpClientResponseStreamToFinalResponse,
getObtainiumHttpError, regExValidator, replaceMatchGroupsInString,
extractVersion, filterApks
```

Each is `fn(...) => Service().fn(...)` — creating a new service instance on every call AND adding a function indirection. Same pattern in `apps_provider_lifecycle.dart:213-215` (`doStringsMatchUnderRegEx`).

**Recommendation:** Either make the service methods static (eliminating the wrapper) or have sources call the services directly. The current approach is the worst of both worlds.

### 2.7 [MEDIUM] Top-level functions for background work hamper testability

**File:** `lib/providers/apps_provider.dart:1067-1405` — `bgUpdateCheck`, `_bgRunUpdateCheck`, `_runBGInstallMode` are top-level functions that construct their own `AppsProvider(isBg: true)` internally. Necessary for WorkManager isolates, but means background logic can't be tested without a full `AppsProvider`.

Also at line 1299, a top-level function reaches into `AppsProvider._eventsController.add(null)` — a private static accessed from outside the class.

**Recommendation:** Wrap in a `BackgroundUpdateOrchestrator` class that accepts a provider (or provider factory). Add a static method `AppsProvider.notifyForegroundOfBgSave()` to encapsulate the controller access.

### 2.8 [MEDIUM] `SourceProvider` mixes singleton, instance, and static state

**File:** `lib/providers/source_provider.dart:909-954`

```dart
class SourceProvider {
  static final SourceProvider _instance = SourceProvider._();
  factory SourceProvider() => _instance;
  List<MassAppUrlSource> massUrlSources = [GitHubStars()]; // mutable instance field
```

`massUrlSources` is a mutable instance field on a singleton — anyone can mutate it at runtime. Combined with the cached `_cachedSources` (line 950), the class has both instance and static state.

**Recommendation:** Make `massUrlSources` `final` (the list reference is already never reassigned) and document the cache invariant.

### 2.9 [MEDIUM] Implementation imports of `easy_localization` internals

**File:** `lib/providers/apps_provider.dart:30-33`

```dart
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
```

Imports private internals of `easy_localization`. Any version bump can break this. Only used by `TranslationLoader.load()`.

**Recommendation:** Encapsulate behind a try/catch with a public-API fallback, or vendor the minimal locale-bootstrapping logic.

### 2.10 [MEDIUM] `SettingsProvider` exposes mutable static state

**File:** `lib/providers/settings_provider.dart:83-84,136`

```dart
static String? _cachedDefaultAppDir;
static bool? _cachedIsTV;
static SharedPreferences? prefsInstance;
```

`prefsInstance` being set as a side effect of `initializeSettings` (line 88) is a hidden global. Any code anywhere can read `SettingsProvider.prefsInstance` without going through an instance — service-locator anti-pattern.

**Recommendation:** Make `prefsInstance` private and expose typed getters/setters only via instance methods.

### 2.11 [MEDIUM] `isFdroidBuild` is a mutable global

**File:** `lib/main.dart:55` — `bool isFdroidBuild = false;` mutated by `main_fdroid.dart:6`.

**Recommendation:** Use `--dart-define=OBTAINIUM_FLAVOR=fdroid` with a `const String.fromEnvironment` check, or use a dedicated `AppFlavor` provider.

### 2.12 [MEDIUM] Page-as-controller anti-pattern via `GlobalKey<AppsPageState>`

**File:** `lib/pages/home.dart:35` — `final GlobalKey<AppsPageState> appsPageKey = GlobalKey<AppsPageState>();`

`AppsPageState` exposes public methods (`refresh`, `showFilterDialog`, `launchCategorizeDialogCallback`, `showMassMarkDialog`, `pinSelectedApps`, `showMoreOptionsBottomSheet`, `shareAppURLs`, `shareConfigLinks`, `shareExport`, `openAppById`, `showSelectedAppActions`, `clearSelected`, `selectThese`, `toggleAppSelected`) called from outside the widget (`home.dart:347` calls `appsPageKey.currentState?.showSelectedAppActions()`). This couples `HomePage` to `AppsPageState`'s implementation, breaks encapsulation, and makes these methods untestable without mounting the widget tree.

**Recommendation:** Move these actions into `AppsProvider` (or a dedicated `AppActionsProvider`) that takes a `BuildContext`/`NavigatorState`. Remove the `GlobalKey`.

### 2.13 [MEDIUM] `ObtainiumError.url` is a mutable public field

**File:** `lib/custom_errors.dart:22`

```dart
String? url;
```

Modified by `withUrlContext` (returns `this` for chaining but mutates in place). Error objects should be immutable. `MultiAppMultiError` has the same problem — all three maps (`rawErrors`, `idsByErrorString`, `appIdNames`) are mutable and public.

**Recommendation:** Make `url` final and have `withUrlContext` return a new instance (or use a copy-with pattern). Seal `MultiAppMultiError`'s maps after construction via `Map.unmodifiable`.

### 2.14 [MEDIUM] `CheckUpdatesException.toString` bypasses URL context formatting

**File:** `lib/custom_errors.dart:179-186`

The `toString` override returns `errors.toString()`, bypassing `ObtainiumError.toString()` which appends URL context. If a URL was attached via `withUrlContext`, it won't appear in the string representation.

**Recommendation:** Include URL context in the override, or remove the override and let `ObtainiumError.toString` handle it.

### 2.15 [LOW] `Logger` abstract class has only one implementation

**File:** `lib/providers/logs_provider.dart:160-208` — `Logger` is abstract with a single `AppLogger` implementation. No test mocks, no alternate implementations.

**Recommendation:** Either add a use case for the abstraction or inline `AppLogger`.

### 2.16 [LOW] `errorWidget` and `ErrorWidget.builder` ordering

**File:** `lib/main.dart:105` — `ErrorWidget.builder` is set before `EasyLocalization.ensureInitialized()` (line 143), so `tr()` can't be used.

**Recommendation:** Move the `ErrorWidget.builder` assignment to after localization is ready.

---

## 3. Code Duplication

### 3.1 `try { ... } catch (e) { rethrowOrWrapError(e); }` wrapper — 27 instances

Nearly every `getLatestAPKDetails` wraps its entire body in this boilerplate. Instances across all source files (full list in §1.7 and the app-sources audit).

**Recommendation:** Move the `rethrowOrWrapError` call into `SourceProvider.getApp` (`source_provider.dart:1079`) where `source.getLatestAPKDetails` is already called inside a try-catch. Or provide a protected template method `getLatestAPKDetailsSafe` in `AppSource` that wraps the subclass implementation.

### 3.2 `sourceRequest` + status code 200 check + `getObtainiumHttpError` — 20+ instances

```dart
final res = await sourceRequest(url, additionalSettings);
if (res.statusCode != 200) {
  throw getObtainiumHttpError(res);
}
```

Appears in virtually every source file (e.g., `apk4free.dart:26-29`, `apkcombo.dart:45-51`, `apkmirror.dart:79-82`, `aptoide.dart:40-43`, `coolapk.dart:54-58`, etc.).

**Recommendation:** Add a base class helper `Future<Response> sourceRequestExpect200(String url, Map<String, dynamic> settings)`.

### 3.3 "Infer app ID, throw `NoReleasesError` if null" — 7 instances

```dart
final String? appId = await tryInferringAppId(standardUrl);
if (appId == null) {
  throw NoReleasesError();
}
```

Instances: `apkpure.dart:185-188`, `apkcombo.dart:120-123`, `coolapk.dart:47-50`, `fdroid.dart:84-87`, `izzyondroid.dart:51-54`, `rustore.dart:55-58`, `tencent.dart:34-37`.

**Recommendation:** Add a base class helper `Future<String> requireInferredAppId(String standardUrl)`.

### 3.4 Boolean setting extraction pattern — 15+ instances

```dart
final bool fallbackToOlderReleases = additionalSettings['fallbackToOlderReleases'] == true;
```

Instances: `github.dart:641-662` (8 booleans), `apkmirror.dart:71-72`, `gitlab.dart:243-244`, `sourcehut.dart:51-52`, `fdroidrepo.dart:184-187`, `fdroid.dart:209-212`, `apkpure.dart:247-248`.

**Recommendation:** The `TypedSettings` class (`source_provider.dart:1205-1237`) already provides `getBool()`. Sources should use `TypedSettings(additionalSettings).getBool('fallbackToOlderReleases')`.

### 3.5 "Confirmation dialog via `GeneratedFormModal` with `items: const []`" — 6 instances

The same pattern of showing a `GeneratedFormModal` with `items: const []` and checking if the result `!= null`:
- `apps.dart:353-364`, `apps.dart:371-390`
- `add_app.dart:209-219`
- `home.dart:220-246`
- `settings.dart:1096-1107`

**Recommendation:** Add a helper to `ui_widgets.dart` (next to the existing `showConfirmDialog` at line 22):

```dart
Future<bool> showContinueCancelDialog(BuildContext context, {
  required String title, String? message, String? continueText,
}) async {
  final result = await showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (ctx) => GeneratedFormModal(
      title: title, items: const [], initValid: true, message: message,
      singleNullReturnButton: continueText ?? tr('continue'),
    ),
  );
  return result != null;
}
```

### 3.6 Loading-spinner button swap — 4 instances

- `import_export.dart:130-139` (`isImporting`)
- `settings.dart:591-600` (`_isRunningBgCheck`)
- `add_app.dart:756-765` and `add_app.dart:852-861` — **near-identical** inline `CircularProgressIndicator` + `IconButton` swap.

**Recommendation:** Extract `LoadingIconButton` and `LoadingButton` widgets into `ui_widgets.dart`.

### 3.7 "Select all / deselect" toggle button — 3 instances

- `apps.dart:761-788` (`_getSelectAllButton`)
- `apps.dart:1386-1403` (inside `_BulkUpdateDialog`)
- `import_export.dart:607-631` (`_buildSelectAllButton`)

All three share the same structure with `ButtonStyle(visualDensity: VisualDensity.compact)` repeated verbatim.

**Recommendation:** Extract a `SelectAllToggleButton` widget.

### 3.8 `Navigator.push` to `AppPage` — 2+ instances with risk of drift

- `app_list_tile.dart:161-169` and `:184-194` (long-press, semantics + touch — identical)
- `apps.dart:689-692`, `apps.dart:1198-1200`, `app.dart:1254-1262`
- `AppPage` is instantiated with `onClose` in two-pane mode (`home.dart:323-327` vs `apps.dart:691`), and the two construction sites can drift.

**Recommendation:** Introduce a `NavHelper` or `Navigator` extension with `pushAppPage(appId)`, `pushSettingsPage()`, `pushAddAppPage({initialUrl})`, `pushLogsPage()`.

### 3.9 Duplicate Obtainium-variant ID check — 5+ instances

```dart
if (app.id == obtainiumId || app.id == '$obtainiumId.fdroid' || app.id == '$obtainiumId.debug') { ... }
```

- `stock_installer.dart:26-28` and `:52-54`
- `apps_provider_install.dart:915-916`
- `main.dart:232` (implicit self-check)

**Recommendation:** Extract `bool isObtainiumVariant(String id) => ...` to a shared constants file.

### 3.10 Concurrency limit `4` duplicated

- `apps_provider_updates.dart:151` — `const maxConcurrent = 4;`
- `source_provider.dart:1160` — `const concurrency = 4;`

**Recommendation:** Single named constant `kDefaultFetchConcurrency`, ideally configurable.

### 3.11 Sorting by `lastUpdateCheck` duplicated

- `apps_provider_updates.dart:81-89` and `:120-128` — identical comparators sorting by `lastUpdateCheck ?? DateTime.fromMicrosecondsSinceEpoch(0)`.

**Recommendation:** Extract `int compareByLastUpdateCheck(String a, String b)`.

### 3.12 BG-install polling block duplicated verbatim

**File:** `lib/providers/apps_provider_install.dart:1121-1157` vs `:1168-1197`

The APK-vs-dir branches each contain a near-identical ~30-line block (`captureInstallBaseline` + `unawaited(installApk/...)` + `waitForPackageInstall` + logging).

**Recommendation:** Extract `_awaitBgInstall(id, baseline, Future installFuture)`.

### 3.13 `apps_provider.dart` imports easy_localization internals

`apps_provider.dart:30-33` imports private internals of `easy_localization` (`easy_localization_controller.dart`, `localization.dart`) for `TranslationLoader`. Any version bump can break this.

### 3.14 Locale-based casing helpers split across two files

- `custom_errors.dart:275` — `lowerCaseIfEnglish(String str)`
- `settings_provider.dart:26` — `lowerCaseUnlessLang(String str, String lang)`

Both conditionally lowercase based on locale.

**Recommendation:** Consolidate into a single utility in `lib/utils/locale_utils.dart`.

### 3.15 Version-text functions with near-identical logic

- `app_list_tile.dart:966-973` — `_VersionLabel.installedVersionText`
- `app_detail_widgets.dart:10-15` — `appInstalledVersionText`

Both compute display text from install/latest version, differing only in format.

**Recommendation:** Unify or have one delegate to the other.

### 3.16 `appsToInstall = moveStrToEnd(...)` repeated 3 times

**File:** `lib/providers/apps_provider_install.dart:910-916`

```dart
appsToInstall = moveStrToEnd(appsToInstall, obtainiumId, strB: obtainiumTempId);
appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.fdroid');
appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.debug');
```

Each re-scans and re-allocates the list. A single `moveToEndAll(arr, [...])` would be cleaner and O(n) instead of O(3n).

---

## 4. Long / Complex Methods to Decompose

| File:Line | Method | Lines | Recommendation |
|---|---|---|---|
| `apps_provider.dart:410-675` | `downloadFile` | 265 | Split into `_probeHeaders`, `_decideResumeStrategy`, `_streamToDisk`, `_finalizeDownload`. |
| `apps_provider.dart:1112-1300` | `bgUpdateCheck` | 188 (top-level) | Already partially decomposed into `_bgRunUpdateUpdate` and `_runBGInstallMode`; main fn still too long. Wrap in `BackgroundUpdateOrchestrator`. |
| `apps_provider_install.dart:139-356` | `downloadApp` | 217 | Extract URL prefetch, file-type detection, extraction, filter, ID-change handling. |
| `apps_provider_install.dart:1089-1238` | `_installDownloadedApp` | 149 | Four-way branch (file vs dir × BG vs normal) with duplicated polling logic (§3.12). |
| `apps_provider_lifecycle.dart:104-179` | `getCorrectedInstallStatusAppIfPossible` | 75 | Comments literally number the steps ("1. Compare…", "2. Reconcile…"). Extract 4 private methods. |
| `source_provider.dart:663-759` | `combinedAppSpecificSettingFormItems` (getter) | 97 | A *getter* that performs logic and mutates items in place. Extract a builder function. |
| `source_provider.dart:563-656` | `_commonAppSettingFormItems` (private getter) | 93 | Used once; inline or make a top-level builder. |
| `github.dart:623-747` | `_fetchReleaseDetails` | 124 | Extract optional latest-tag verification, merging, sorting, target selection. |
| `github.dart:511-619` | `_selectGitHubTargetRelease` | 108 | Complex loop with prerelease/draft skipping, title/notes regex filtering, asset extraction. |
| `gitlab.dart:126-278` | `getLatestAPKDetails` | 152 | Extract `_extractAssetsFromRelease`, `_extractUploadsFromDescription`, `_rewriteJenkinsArtifactUrls`. |
| `fdroidrepo.dart:173-318` | `getLatestAPKDetails` | 145 | Extract `_findAppInRepo`, `_selectReleases`, `_buildApkUrls`. |
| `html.dart:389-504` | `getLatestAPKDetails` | 115 | Extract `_resolveIntermediateLinks`, `_resolveVersion`, `_resolvePseudoVersion`. |
| `fdroid.dart:202-309` | `getAPKUrlsFromFDroidPackagesAPIResponse` | 107 | Complex release selection with suggested version code, filter regex, auto-select. |
| `apps.dart:998-1184` | `AppsPageState.build` | 186 | Computes filter/sort/group + 3 loops + post-frame callbacks inside `build()`. See §7 and §8. |
| `settings.dart:273-545` | `_SettingsPageState.build` | 272 | Builds 6 large local widget variables inline. Extract each into a private `StatelessWidget`. |
| `add_app.dart:681-931` | `AddAppPageState.build` | 250 | Extract `_buildUrlInputRow`, `_buildOverrideSourceDropdown`, `_buildSearchRow`, `_buildSourceNoteCard`, `_buildImportSection`. |
| `app.dart:1199-1335` | `_AppPageState.build` | 136 | Already partially extracted; move side-effects out (§1.14) and split the final ternary into `_buildWebViewBody` + `_buildDetailBody`. |
| `app_list_tile.dart:315-541` | `AppListTile.build` | 226 | Extract `_AppListTileTrailing`, `_SwipeBackground`, `_AppListTileContent`. See §8. |
| `generated_form_renderer.dart:552-646` | `_GeneratedFormState.build` | 94 | Extract `_buildTileModeColumn` and `_buildPlainColumn`. |
| `category_editor.dart:228-325` | `_CategoryEditorSheetState.build` | 97 | Extract `_buildPaletteGrid`. |

---

## 5. Dead Code to Remove

| File:Line | Item | Lines saved |
|---|---|---|
| `apps_provider.dart:194-198` | `moveStrToEndMapEntryWithCount` — zero call sites (confirmed via grep). | 5 |
| `ui_widgets.dart:158-205` | `HighlightableButton` — never instantiated (confirmed via grep). | 47 |
| `generated_form_model.dart:7-19` | `GeneratedFormFieldState` — never referenced. | 13 |
| `generated_form_model.dart:21-111` | `FormFieldDefinition` class + `toGeneratedFormItem()` — never used outside its own file (confirmed via grep). | 91 |
| `generated_form_model.dart:130-189` | `GeneratedFormItem.toDefinition()` — never called outside the file. | 60 |
| `app_list_tile.dart:536` | Empty `onDismissed: (direction) {}` on `Dismissible` — `confirmDismiss` controls dismissal; `onDismissed` is never invoked. | 1 |
| `app_list_tile.dart:144-150` | `_lastAppId` field in `AppIconWidget.didUpdateWidget` — redundant; use `oldWidget.appId` comparison. | 2 |
| `app.dart:54` | `webViewReady` public getter — never used outside the class. | 1 |
| `jenkins.dart:33` | `trimJobUrl` — no-op wrapper around `sourceSpecificStandardizeURL`. | 2 |
| `rustore.dart:91-93` | `downloadDetails == null` check — `decodeJsonBody` never returns null. | 1 |

**Total: ~223 lines of dead code.**

Additionally, several methods are public but only used internally and should be made private:
- `fdroidrepo.dart:51` — `removeQueryParamsFromUrl`
- `neutroncode.dart:39,43` — `monthNameToNumberString`, `formatDateForParsing`
- `huaweiappgallery.dart:26,47` — `getDlUrl`, `appIdFromRedirectDlUrl`
- `vivoappstore.dart:117` — `parseVivoAppId`
- `uptodown.dart:9` — `parseUptodownDate`

---

## 6. Hardcoded Values to Extract as Constants

The codebase already has a good block of named constants at `apps_provider.dart:46-58` (`_defaultRetries`, `_retryDelaySeconds`, etc.) and `notifications_provider.dart:20-25`. These remain:

### 6.1 API base URLs hardcoded inline

| File:Line | Value |
|---|---|
| `coolapk.dart:51` | `'https://api2.coolapk.com'` |
| `aptoide.dart:54` | `'https://ws2.aptoide.com/api/7/getApp/app_id/$id'` |
| `rustore.dart:60,86` | `'https://backapi.rustore.ru/...'` |
| `vivoappstore.dart:8-9,73-74,103-104` | `'https://h5coml.vivo.com.cn/...'`, `'https://h5-api.appstore.vivo.com.cn/...'` |
| `apkpure.dart:204` | `'https://tapi.pureapk.com/v3/...'` |
| `fdroid.dart:102` | `'https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/$appId.yml'` |
| `telegramapp.dart:29,43` | `'https://t.me/s/TAndroidAPK'`, `'https://telegram.org/dl/android/apk'` |

`vivoappstore.dart:8-9` already uses `static const appDetailUrl` — good practice the others should follow.

### 6.2 Hardcoded client versions / device fingerprints

| File:Line | Value |
|---|---|
| `coolapk.dart:147-157` | Full CoolApk client User-Agent, X-App-Version (12.4.2), X-App-Code (2208241) |
| `coolapk.dart:179-183` | Hardcoded device manufacturer/brand/model/build |
| `rustore.dart:27` | `'ruStoreVerCode': '1105002'` |
| `apkcombo.dart:35` | `'User-Agent': 'curl/8.0.1'` |
| `html.dart:339` | Default User-Agent string |
| `apkmirror.dart:48` | Fallback `'1.0.0'` version |

### 6.3 Pagination sizes

`github.dart:786`, `gitlab.dart:158`, `codeberg.dart:51,67`, `githubstars.dart:29` — all use `per_page=100` or `limit=100` inline.

### 6.4 Magic numbers in providers

| File:Line | Value | Suggested name |
|---|---|---|
| `apps_provider_updates.dart:107` | `Duration(milliseconds: 250)` | `_refreshProgressIntervalMs` |
| `apps_provider_updates.dart:145` | `Duration(seconds: 3)` | `_incrementalSaveInterval` |
| `apps_provider_updates.dart:151` | `maxConcurrent = 4` | `_maxConcurrentUpdateChecks` |
| `apps_provider_updates.dart:168` | `maxRetries = 5` | `_handshakeRetryCount` |
| `apps_provider_updates.dart:171` | `250 + rng.nextInt(501)` ms | `_handshakeRetryBaseMs` / `_handshakeRetryJitterMs` |
| `apps_provider.dart:948` | `Duration(seconds: 2)` auto-export debounce | `_autoExportDebounceSeconds` |
| `apps_provider.dart:1259-1263` | `100`, `9900` notification ID range | named constants |
| `apps_provider.dart:1379` | `10000` retry task name salt | `_retryNameSaltRange` |
| `apps_provider_install.dart:412` | `Duration(minutes: 5)` foreground wait | `_foregroundWaitTimeout` |
| `apps_provider_install.dart:694-699` | `'/storage/emulated/0'` fallback | `_defaultStorageRoot` |
| `settings_provider.dart:243` | `?? 360` default update interval | `_defaultUpdateIntervalMinutes` |
| `logs_provider.dart:64` | `Duration(days: 7)` | `_logRetentionDays` |
| `liteapks.dart:43` | `10800` (3 hours in seconds) | named constant |
| `github.dart:883` | `3600` (fallback seconds) | named constant |

### 6.5 Pervasive hardcoded padding/spacing in UI

| Value | Occurrences | Examples |
|---|---|---|
| `EdgeInsets.fromLTRB(16, 0, 16, 0)` | ~6 | `app.dart:678,737`; `settings.dart:498`; `apps.dart:859,920` |
| `EdgeInsets.symmetric(horizontal: 16)` | ~5 | `apps.dart:871`; `settings.dart:312,377`; `app.dart:1317` |
| `EdgeInsets.all(16)` | ~5 | `apps.dart:289,924`; `import_export.dart:143`; `app.dart:682`; `add_app.dart:889` |
| `SizedBox(height: 20)` as section spacer | ~8 | `app.dart:734,954,1290,1292,1300,1303` |
| `SizedBox(height: 8)` | ~10 | across all files |
| `SizedBox(width: 12)` | ~3 | `settings.dart:317,382`; `app.dart:697` |

**Recommendation:** Add to `theme.dart`:

```dart
abstract final class AppPaddings {
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: 16);
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 0, 16, 0);
  static const EdgeInsets cardInner = EdgeInsets.all(16);
}
abstract final class AppSpacings {
  static const double sectionGap = 20;
  static const double elementGap = 8;
  static const double tightGap = 4;
}
```

### 6.6 Hardcoded `fontSize: 12` — accessibility concern

~11 occurrences across `apps.dart`, `app.dart`, `import_export.dart`, `add_app.dart`, `settings.dart`. Hardcoded font sizes ignore `MediaQuery.textScaler` and user font-size settings.

**Recommendation:** Replace with `Theme.of(context).textTheme.bodySmall` / `labelSmall`.

### 6.7 Hardcoded font family strings

**File:** `lib/main.dart:345,351` — `'SystemFont'` and `'Montserrat'` as string literals.

**Recommendation:** `const String kDefaultFontFamily = 'Montserrat'; const String kSystemFontFamily = 'SystemFont';`

### 6.8 Hardcoded border radii

- `apps.dart:1478` (`Radius.circular(28)`) — duplicates `theme.dart:15` (`BorderRadius.circular(28)`).
- `app.dart:802` (`BorderRadius.circular(14)`) — duplicates the `AppIcon` `radius` param.
- `app.dart:888` (`BorderRadius.circular(4)`) — magic number.

---

## 7. State Management & Rebuild Efficiency

### 7.1 `AppsPage` watches entire `AppsProvider`

**File:** `lib/pages/apps.dart:1000` — `final appsProvider = context.watch<AppsProvider>();`

`AppsProvider` notifies on every app change, every download progress tick, every icon load. Watching it wholesale means `AppsPage` rebuilds on every download progress update for every app — even though tiles use `ValueListenableBuilder` for progress.

**Fix:** Use granular `context.select` like `app.dart:1208-1217` does:

```dart
final areDownloadsRunning = context.select<AppsProvider, bool>((p) => p.areDownloadsRunning());
final loadingApps = context.select<AppsProvider, bool>((p) => p.loadingApps);
final refreshProgressValue = context.select<AppsProvider, double?>((p) => p.refreshProgress.value);
```

### 7.2 `SettingsPage` watches entire `SettingsProvider`

**File:** `lib/pages/settings.dart:275` — `final SettingsProvider settingsProvider = context.watch<SettingsProvider>();`

A single toggle flip rebuilds the ~270-line `build()`. The author already extracted `_UpdateIntervalSliderTile` (line 859) for exactly this reason — apply the same treatment to the color picker, theme mode, and every `ToggleTile`.

### 7.3 `app.dart` has a discarded `context.select` result

**File:** `lib/pages/app.dart:1211-1213`

```dart
context.select<AppsProvider, double?>(
  (p) => p.apps[widget.appId]?.downloadProgress,
);
```

The return value is discarded — the select is used purely for its rebuild-triggering side effect. Confusing and fragile.

**Fix:** Assign it, or replace with a `ValueListenableBuilder` on the download progress notifier.

### 7.4 `SettingsProvider` has no batching

**File:** `lib/providers/settings_provider.dart` — 46 `notifyListeners()` calls, one per setter. Changing 5 settings on save triggers 5 full Provider rebuilds.

**Fix:**

```dart
void batchUpdate(void Function() updates) {
  _silent = true;
  updates();
  _silent = false;
  notifyListeners();
}
```

### 7.5 `notify()` wrapper is a code smell

**File:** `lib/providers/apps_provider.dart:907-909` — `void notify() => notifyListeners();`

Exists because Dart extensions in separate files can't see `@protected` members. If the split were done with `part of` instead, `notifyListeners` would be directly accessible. Or, if concerns were extracted into collaborator services (§2.1), each service would have its own notifier and the wrapper wouldn't be needed.

### 7.6 `AppsProvider.dispose` doesn't cancel in-flight downloads

**File:** `lib/providers/apps_provider.dart:1032-1040` — cancels subscriptions and the debounce timer but doesn't iterate `_downloadCancellations` to cancel them. If the provider is disposed mid-download, downloads keep running and will try to mutate `apps[...]` and call `notify()` on a disposed notifier. The `_disposed` flag isn't checked in `downloadApp` or its callbacks.

**Fix:** Iterate and cancel all tokens in `dispose()`; add `if (_disposed) return;` guards in async download callbacks.

### 7.7 `DownloadState` held by reference — intentional but subtle

**File:** `lib/providers/apps_provider.dart:68-101`

`DownloadState` is shared by reference across `AppInMemory` copies so UI listeners keep updating after `saveApps` replaces the map entry. `deepCopy()` and `copyWith()` both preserve the same `download` reference. Correct, but easy to break — a unit test asserting this invariant would be valuable.

### 7.8 `ImportFromURLListController` is an orphan `ChangeNotifier`

**File:** `lib/pages/import_export.dart:911-991` — the only non-`Provider` `ChangeNotifier` in the pages, provided via `ChangeNotifierProvider.value` (line 82). Inconsistent with the rest of the codebase.

**Fix:** Fold into `AppsProvider` or `SourceProvider`, or make it a full Provider.

---

## 8. UI / Widget Tree Decomposition

### 8.1 `AppListTile.build` — 226 lines

**File:** `lib/components/app_list_tile.dart:315-541`

Constructs: `LayoutBuilder` for trailing row, category gradient stops, two near-identical swipe backgrounds, `ValueListenableBuilder` wrapping everything, `Semantics` with custom actions, `ListTile` with many properties, TV-mode conditional wrapping, `Dismissible` with `confirmDismiss` logic.

**Recommendation:** Extract:
- `_AppListTileTrailing` (LayoutBuilder + update button + version label)
- `_SwipeBackground` (parameterized by icon + label, eliminating the duplicate install/update backgrounds)
- `_AppListTileContent` (ValueListenableBuilder + Semantics + Container + ListTile)
- `Dismissible` wrapper stays in `AppListTile.build`, delegating child to `_AppListTileContent`

### 8.2 `AppsPageState.build` — 186 lines with business logic inside `build()`

**File:** `lib/pages/apps.dart:998-1184`

Inside `build()`: watches two providers, schedules post-frame callback for auto-refresh, computes the full app list with filter/sort/reorder, computes update/new-install/track-only ID sets with three separate O(n²) loops, computes group-by buckets with two `for` loops, sorts group keys, returns a 70-line widget tree. The computation runs on every rebuild.

**Recommendation:**
- Move filtering/sorting/grouping to a pure function `_computeGroupedList(apps, filter, settings)` called from a selector, not from `build()`.
- Move the track-only partition (lines 1060-1077) to a single `partitionAppIdsByUpdateKind(apps)` helper (also used by the bottom-sheet version at `apps.dart:464-493`).
- Move the auto-refresh check (lines 1004-1012) and selection-pruning (lines 1016-1032) out of `build()` into `didChangeDependencies` / a listener.
- Split the 70-line widget tree into `_buildScaffold()` / `_buildScrollBody()`.

### 8.3 `_SettingsPageState.build` — 272 lines

**File:** `lib/pages/settings.dart:273-545`

Builds 6 large local widget variables inline (`colorPicker`, `themeModeControl`, `sortDropdown`, `orderControl`, `localeDropdown`, `colourSchemeDropdown`).

**Recommendation:** Move each into its own private `StatelessWidget` (`_ThemeColorPickerTile`, `_ThemeModeSegmentedButton`, `_SortColumnDropdown`, `_SortOrderSegmentedButton`, `_LocaleDropdown`, `_ColourSchemeDropdown`). The source-specific form (lines 456-486) should also be its own widget. `build()` becomes ~40 lines of section composition.

### 8.4 `AddAppPageState.build` — 250 lines

**File:** `lib/pages/add_app.dart:681-931`

Deeply nested inline `GeneratedForm` declarations, inline `FutureBuilder` (lines 880-921), inline conditional spreads.

**Recommendation:** Extract `_buildUrlInputRow`, `_buildOverrideSourceDropdown`, `_buildSearchRow`, `_buildSourceNoteCard`, `_buildImportSection`. The 250-line method becomes ~40 lines of composition.

### 8.5 Move `LogsPage` to its own file

**File:** `lib/pages/settings.dart:1035-1280` — `LogsPage` is a full 245-line page living inside `settings.dart`.

**Recommendation:** Move to `lib/pages/logs.dart`.

### 8.6 Move `_BulkUpdateDialog` and `_ExternalInstallerTile._choose` to `components/`

- `apps.dart:1241-1435` — `_BulkUpdateDialog` (194 lines) is a private widget that could live in `components/`.
- `settings.dart:1319-1417` — the `_choose` dialog inside `_ExternalInstallerTile` should be its own widget.

### 8.7 Generated form system: two-phase initialization is confusing

**File:** `lib/components/generated_form_renderer.dart:336-371,552-583`

`_initFormData` initializes `GeneratedFormSwitch` items as `const SizedBox.shrink()` (line 362) and `GeneratedFormSubForm` items as `Container()` (line 360). Then `build()` replaces these placeholders with actual widgets. The replacement happens on every build, creating new widget instances each time.

**Recommendation:** Single-pass: build the correct widget in `build()` from the model directly.

### 8.8 `TypeAheadField` used for all text fields, even without autocomplete

**File:** `lib/components/generated_form_renderer.dart:215`

Every `GeneratedFormTextField` is rendered as a `TypeAheadField`, even when `autoCompleteOptions` is null (line 274-277 returns null from `suggestionsCallback`). Adds `flutter_typeahead` overhead to every text input.

**Recommendation:** Use a standard `TextFormField` when `autoCompleteOptions` is null; only use `TypeAheadField` when autocomplete is needed.

### 8.9 SubForm key manipulation via string concatenation is fragile

**File:** `lib/components/generated_form_renderer.dart:444-446`

```dart
y.key = '${y.key.toString()},$internalFormKey';
```
Then split on `,` at line 451-453. If a field key ever contains a comma, it breaks.

**Recommendation:** Use a wrapper object or nested maps instead of string-encoding the hierarchy.

### 8.10 `shapeCardTiles` infers `isFirst`/`isLast` by comparing border-radius values

**File:** `lib/components/ui_widgets.dart:424-481`

`_wrapChildWithRadius` infers `isFirst`/`isLast` by comparing `r.topLeft.x == connectedTileBigRadius` (lines 439, 449). If the constant changes or a different radius is used, the logic breaks silently.

**Recommendation:** Pass explicit `isFirst`/`isLast` metadata alongside the widget list instead of inferring from border-radius values.

---

## 9. Cross-Cutting Conventions to Standardize

### 9.1 Provider initialization pattern — three different patterns

1. **`didChangeDependencies` + `_providersInitialized` guard** (correct): `apps.dart:67-75`, `app.dart:112-121`, `add_app.dart:66-75`.
2. **`initState` + `context.read`** (fragile): `home.dart:40-44`, `settings.dart:38-46`.
3. **Inline `context.read`/`context.watch` in `build()`** (fine): everywhere.

**Standardize on pattern 1** across all pages.

### 9.2 App bar — inconsistent

`apps.dart`, `add_app.dart`, `settings.dart` use `CustomAppBar`. `app.dart:529-537` builds a raw `AppBar` directly. `settings.dart:1232` (`LogsPage`) uses a raw `SliverAppBar`. `import_export.dart:91` uses a raw `SliverAppBar`.

**Standardize on `CustomAppBar`** where a simple pinned title suffices.

### 9.3 Source `name` assignment — constructor vs getter override

**Constructor assignment** (non-localized): `github.dart:16`, `gitlab.dart:18`, `apkpure.dart:22`, `apkcombo.dart:8`, `apkmirror.dart:16`, `sourceforge.dart:13`, `itchio.dart:16`, `jenkins.dart:13`, `neutroncode.dart:8`, `rockmods.dart:9`, `liteapks.dart:10`, `apk4free.dart:7`, `farsroid.dart:15`, `rustore.dart:13`, `sourcehut.dart:12`.

**Getter override** (localized): `fdroid.dart:17`, `fdroidrepo.dart:15`, `coolapk.dart:21`, `huaweiappgallery.dart:8`, `vivoappstore.dart:12`, `tencent.dart:9`, `telegramapp.dart:9`, `direct_apk_link.dart:14`.

**Impact:** Some source names appear translated in the UI and some don't.

**Recommendation:** Standardize on getter override for all.

### 9.4 JSON decode error handling — inconsistent

- **With try-catch and logging**: `coolapk.dart:61-71`, `apkpure.dart:211-222`, `farsroid.dart:78-88`.
- **Without try-catch** (crash on malformed JSON): `jenkins.dart:47`, `gitlab.dart:149`, `aptoide.dart:60`, `vivoappstore.dart:110`, `liteapks.dart:93`, `rustore.dart:66`.
- **With try-catch but no logging**: `tencent.dart:60-62`.

**Recommendation:** Standardize on try-catch + logging.

### 9.5 `DateFormat` import inconsistency

- `sourcehut.dart:4` explicitly imports `package:intl/intl.dart`.
- `uptodown.dart`, `itchio.dart`, `huaweiappgallery.dart`, `apkcombo.dart` rely on `easy_localization` re-exporting `DateFormat` without an explicit import.

**Recommendation:** Add explicit `intl` imports wherever `DateFormat` is used.

### 9.6 `forSelection` parameter mostly ignored

Only `direct_apk_link.dart:50` uses `forSelection`. The other 28 sources accept it but ignore it.

**Recommendation:** Either remove the parameter from the base class signature or document that it's optional.

### 9.7 Fallback app name inconsistency

- Some use `tr('app')`: `apkpure.dart:129`, `rustore.dart:72`, `tencent.dart:75`, `uptodown.dart:125`, `vivoappstore.dart:51`, `aptoide.dart:77`.
- Some use `name` (the source name): `neutroncode.dart:97`, `fdroid.dart:304`.
- Some use URL-derived strings: `html.dart:499`, `apk4free.dart:151`.

**Recommendation:** Standardize on `tr('app')` for the fallback.

### 9.8 `Theme.of(context)` called many times without caching

- `app.dart:827-836` — 4 calls to `Theme.of(context)`.
- `app.dart:1014-1015,1032-1033,1047` — 6 calls.
- `settings.dart:493,122,135,136` — scattered.

**Recommendation:** Cache `final theme = Theme.of(context);` / `final cs = theme.colorScheme;` / `final tt = theme.textTheme;` at the top of each builder, as is already done in `app.dart:694-695` and `apps.dart:911`.

### 9.9 `capitalizeFirst` defined in wrong file

**File:** `lib/components/app_list_tile.dart:611-612` — only used in `lib/pages/apps.dart:736`.

**Recommendation:** Move to `lib/utils/string_utils.dart`.

### 9.10 `generateRandomLightColor` defined in wrong file

**File:** `lib/components/generated_form_renderer.dart:18` — imported by `category_editor.dart:6` and used by `apps_provider_lifecycle.dart:542`.

**Recommendation:** Move to `lib/utils/color_utils.dart`.

### 9.11 `formatDownloadSize` defined in `apps_provider.dart`

Used by `app_list_tile.dart` and `notifications_provider.dart`. A formatting utility doesn't belong in a state provider.

**Recommendation:** Move to `lib/utils/format_utils.dart`.

### 9.12 `captureInstallBaseline` / `waitForPackageInstall` misplaced

**File:** `lib/providers/apps_provider.dart:768-798` — used by both `ExternalInstaller` (`external_installer.dart:77,133`) and `apps_provider_install.dart` (lines 1122,1133,1169,1173). Installer-adjacent utilities don't belong in the apps provider.

**Recommendation:** Move to `lib/installers/install_utils.dart` or `lib/services/install_polling.dart`.

---

## 10. i18n / Accessibility

### 10.1 Unlocalized strings (bugs)

| File:Line | String | Fix |
|---|---|---|
| `app.dart:864` | `'(OS installed $realVersion)'` | Add translation key with `{osVersion}` arg |
| `main.dart:117,122` | `'An unexpected error occurred.'`, `'Close'` | Move `ErrorWidget.builder` after localization init, or accept English-only |
| `home.dart:238` | `fontFamily: 'monospace'` | Reference a theme font |
| `app.dart:75` | `url == 'placeholder'` magic string | Named constant |

### 10.2 Hardcoded `fontSize: 12` ignores text scaling

~11 occurrences. Replace with `textTheme.bodySmall` / `labelSmall` for accessibility.

### 10.3 `lowerCaseUnlessLang` / `lowerCaseIfEnglish` split

Two helpers doing overlapping work (§3.14). Consolidate.

---

## 11. Suggested Phased Execution Plan

The recommendations vary widely in risk and effort. The plan below is ordered to minimize risk: dead-code removal and bug fixes first (no behavior change for existing passing paths), then internal refactors (no API change), then architectural reorganization (largest blast radius, done last).

### Phase 1 — Quick wins (low risk, high value)

**Estimate: ~1 day. No behavior change for existing passing paths.**

1. **Remove dead code (§5):** `moveStrToEndMapEntryWithCount`, `HighlightableButton`, `GeneratedFormFieldState`, `FormFieldDefinition` + `toGeneratedFormItem` + `toDefinition` (~223 lines), empty `onDismissed`, `_lastAppId`, `webViewReady` getter, `Jenkins.trimJobUrl`, `RuStore` null-dead-code.
2. **Fix ReceivePort leak (§1.1):** one-line `close()` before re-register.
3. **Fix GitHub draft skip counter (§1.4):** single counter for both prereleases and drafts.
4. **Fix GitHub sort comparator symmetry (§1.5):** same sentinel on both sides.
5. **Fix FDroidRepo `selectedReleases[0]` empty check (§1.6):** add `NoReleasesError`.
6. **Fix double `rethrowOrWrapError` in APKPure / SourceForge (§1.7):** remove inner wraps; narrow SourceForge's catch.
7. **Fix `prevApp` reset in `app.dart` `didUpdateWidget` (§1.12):** add `prevApp = null;`.
8. **Fix `context.read` in `home.dart` `initState` (§1.13):** move to `didChangeDependencies` with guard.
9. **Fix unlocalized `(OS installed ...)` string (§1.15):** add translation key.
10. **Add `mounted` guards to empty `setState` in async callbacks (§1.16):** especially `apps.dart:142-144`.
11. **Make internal helper methods private (§5):** `removeQueryParamsFromUrl`, `monthNameToNumberString`, etc.

### Phase 2 — Bug fixes with slightly higher risk

**Estimate: ~1-2 days.**

1. **Move `extractTarballFile` off the UI thread (§1.2):** `Isolate.run` / `compute`.
2. **Fix FDroidRepo mutable `_appIdFoundInUrl` on cached source (§1.3):** return from `runOnAddAppInputChange`.
3. **Add `_disposed` guard to `cancelDownload` + clear static in `dispose` (§1.8).**
4. **Expose `AppsProvider.ready` future (§1.9):** Completer-backed; have `apkDir` callers await it.
5. **Narrow `catch (e)` in `SourceProvider.getSource` to `ObtainiumError` (§1.10).**
6. **Centralize `apps[id]!.app =` mutation (§1.11):** single `_updateApp` method; defer `installedVersion = latestVersion` until install confirmation.
7. **Move side effects out of `build()` (§1.14):** `_maybeProbeDownloadSize` and post-frame callbacks into `didUpdateWidget` / listeners.
8. **Fix `initValid: false` override (§1.22):** preserve caller's `initValid` when `isBuilding == true`.
9. **Reset `webViewLoaded` on appId change (§1.23).**
10. **Fix `_fontLoaded` preventing reload (§1.17):** track previous value.
11. **Use `appId.hashCode` for notification IDs (§1.18).**
12. **Drain headers response body (§1.19).**
13. **Add explicit null guard in `reconcileVersionDifferences` (§1.20).**
14. **Use `VersionService` comparison in `findAppIdsWithPendingUpdates` (§1.21).**
15. **Move `LogsProvider` cleanup out of constructor (§1.26).**
16. **Move `setAppLocale` out of `MaterialApp.builder` (§1.25).**
17. **Cancel in-flight downloads in `AppsProvider.dispose` (§7.6).**

### Phase 3 — Duplication removal and helper extraction

**Estimate: ~2-3 days. No external API change.**

1. **Eliminate `try/catch + rethrowOrWrapError` boilerplate (§3.1):** wrap once in `SourceProvider.getApp` or via a `getLatestAPKDetailsSafe` template method.
2. **Add `sourceRequestExpect200` helper (§3.2):** eliminates 20+ status-code checks.
3. **Add `requireInferredAppId` helper (§3.3):** eliminates 7 "infer + throw" blocks.
4. **Adopt `TypedSettings` throughout (§3.4):** replaces 15+ `additionalSettings['key'] == true` checks.
5. **Add `showContinueCancelDialog` helper (§3.5):** eliminates 6 `GeneratedFormModal(items: [])` duplications.
6. **Extract `LoadingIconButton` / `LoadingButton` (§3.6):** eliminates 4 duplications.
7. **Extract `SelectAllToggleButton` (§3.7):** eliminates 3 duplications.
8. **Add `NavHelper` / `Navigator` extension (§3.8):** eliminates `Navigator.push` duplication and drift risk.
9. **Extract `isObtainiumVariant` helper (§3.9):** eliminates 5+ duplications.
10. **Extract `compareByLastUpdateCheck` (§3.11).**
11. **Extract `_awaitBgInstall` helper (§3.12):** eliminates verbatim 30-line duplication.
12. **Extract `moveToEndAll` (§3.16):** single O(n) call instead of 3× O(n).
13. **Move utilities to `lib/utils/` (§9.9, §9.10, §9.11, §9.12):** `capitalizeFirst`, `generateRandomLightColor`, `formatDownloadSize`, `captureInstallBaseline`/`waitForPackageInstall`, `compareAlphaNumeric`, `grabLinksCommon`, etc.
14. **Consolidate locale helpers (§3.14).**
15. **Consolidate version-text functions (§3.15).**
16. **Extract `AppPaddings` / `AppSpacings` constants (§6.5).**
17. **Replace hardcoded `fontSize: 12` with `textTheme` (§6.6).**
18. **Extract named constants for magic numbers (§6.4) and API URLs (§6.1).**

### Phase 4 — Long method decomposition

**Estimate: ~3-4 days. No external API change.**

1. **Decompose `downloadFile` (265 lines) into 4 helpers (§4).**
2. **Decompose `downloadApp` (217 lines) (§4).**
3. **Decompose `_installDownloadedApp` (149 lines) — uses `_awaitBgInstall` from Phase 3 (§4).**
4. **Decompose `getCorrectedInstallStatusAppIfPossible` (75 lines) into 4 private methods (§4).**
5. **Decompose `bgUpdateCheck` (188 lines) (§4).**
6. **Decompose `gitlab.dart` `getLatestAPKDetails` (152 lines) (§4).**
7. **Decompose `fdroidrepo.dart` `getLatestAPKDetails` (145 lines) (§4).**
8. **Decompose `html.dart` `getLatestAPKDetails` (115 lines) (§4).**
9. **Decompose `github.dart` `_fetchReleaseDetails` (124 lines) and `_selectGitHubTargetRelease` (108 lines) (§4).**
10. **Decompose `fdroid.dart` `getAPKUrlsFromFDroidPackagesAPIResponse` (107 lines) (§4).**
11. **Convert `combinedAppSpecificSettingFormItems` getter to a builder function (§4).**
12. **Decompose `AppListTile.build` (226 lines) into `_AppListTileTrailing`, `_SwipeBackground`, `_AppListTileContent` (§8.1).**
13. **Decompose `AppsPageState.build` (186 lines):** move logic out of `build()`, extract `_computeGroupedList`, `partitionAppIdsByUpdateKind` (§8.2).
14. **Decompose `_SettingsPageState.build` (272 lines) into 6 private `StatelessWidget`s (§8.3).**
15. **Decompose `AddAppPageState.build` (250 lines) into 5 builder methods (§8.4).**
16. **Move `LogsPage` to `lib/pages/logs.dart` (§8.5).**
17. **Move `_BulkUpdateDialog` and `_ExternalInstallerTile._choose` to `components/` (§8.6).**
18. **Simplify generated form: single-pass build, `TextFormField` when no autocomplete, stable subform IDs (§8.7, §8.8, §8.9).**
19. **Replace `shapeCardTiles` radius-comparison heuristic with explicit metadata (§8.10).**

### Phase 5 — State management and rebuild efficiency

**Estimate: ~2 days. No external API change.**

1. **Switch `AppsPage` from `context.watch<AppsProvider>()` to granular `context.select` (§7.1).**
2. **Switch `SettingsPage` to per-control `StatelessWidget`s with their own `context.select` (§7.2).**
3. **Fix discarded `context.select` in `app.dart` (§7.3).**
4. **Add `SettingsProvider.batchUpdate` (§7.4).**
5. **Remove `notify()` wrapper by converting extensions to `part of` OR by extracting collaborator services (§7.5).**
6. **Fold `ImportFromURLListController` into a provider (§7.8).**
7. **Move business logic out of State widgets:** `handleAdditionalOptionChanges` (`app.dart:354-414`), `_maybeProbeDownloadSize` (`app.dart:67-109`), `addApp` (`add_app.dart:222-304`), `runSearch` (`add_app.dart:306-453`), `interpretLink` (`home.dart:182-283`) — all should delegate to providers (§3.1 of the pages audit).
8. **Replace `waitUntil` polling in `home.dart:68-79` with a `Completer` / listener (§8.4 of the pages audit).**
9. **Remove `GlobalKey<AppsPageState>` and move actions to a provider (§2.12).**

### Phase 6 — Architectural reorganization (highest risk)

**Estimate: ~5-7 days. Largest blast radius; do last, with tests in place.**

1. **Extract `DownloadService` from `apps_provider.dart` (~400 lines) (§2.1).**
2. **Extract `InstallService` (~800 lines) (§2.1).**
3. **Extract `VersionReconciler` (~150 lines) (§2.1).**
4. **Extract `BackgroundUpdateOrchestrator` (~340 lines) (§2.1, §2.7).**
5. **Extract `AppPersistence` (~250 lines) (§2.1).**
6. **Move `TranslationLoader` and `NativeFeatures` to `lib/util/` (§2.1).**
7. **Move `AppSource` to `lib/app_sources/app_source.dart` (§2.2).**
8. **Move `App`/`AppNames`/`APKDetails`/`TypedSettings` to `lib/models/` (§2.2).**
9. **Move `HttpService`/`VersionService`/`ApkFilterService` to `lib/services/` (§2.2).**
10. **Move JSON migration logic to `lib/providers/app_json_migration.dart` (§2.2).**
11. **Make `APKDetails` and `AppNames` immutable with `copyWith` (§2.3).**
12. **Extract `GitHostingSource` base class for GitHub/GitLab/Codeberg (§2.4).**
13. **Move HTML utilities out of `html.dart` (§2.5).**
14. **Eliminate top-level delegation functions; make service methods static or call services directly (§2.6).**
15. **Make `ObtainiumError` and `MultiAppMultiError` immutable (§2.13).**
16. **Fix `CheckUpdatesException.toString` to include URL context (§2.14).**
17. **Replace `isFdroidBuild` mutable global with `--dart-define` (§2.11).**
18. **Make `SettingsProvider.prefsInstance` private (§2.10).**
19. **Encapsulate `easy_localization` internals behind a try/catch (§2.9).**
20. **Make `SourceProvider.massUrlSources` truly `final` and document cache invariant (§2.8).**
21. **Inline `Logger` abstract class or add a use case (§2.15).**

---

## Appendix A — File:Line Reference Index

### Bugs

| ID | File:Line |
|---|---|
| 1.1 | `lib/providers/notifications_provider.dart:321-338` |
| 1.2 | `lib/providers/apps_provider_install.dart:430-471` |
| 1.3 | `lib/app_sources/fdroidrepo.dart:12,32,111-118` |
| 1.4 | `lib/app_sources/github.dart:522-531` |
| 1.5 | `lib/app_sources/github.dart:460,470` |
| 1.6 | `lib/app_sources/fdroidrepo.dart:283` |
| 1.7 | `lib/app_sources/apkpure.dart:259-268`; `lib/app_sources/sourceforge.dart:93-106` |
| 1.8 | `lib/providers/apps_provider.dart:982,924-931` |
| 1.9 | `lib/providers/apps_provider.dart:871-887` |
| 1.10 | `lib/providers/source_provider.dart:990-992,1004-1006` |
| 1.11 | `lib/providers/apps_provider_install.dart:119,130,159,510,629,657,864` |
| 1.12 | `lib/pages/app.dart:57,1229-1237,124-136` |
| 1.13 | `lib/pages/home.dart:42-44` |
| 1.14 | `lib/pages/apps.dart:1008,1018`; `lib/pages/app.dart:1225,1234` |
| 1.15 | `lib/pages/app.dart:864` |
| 1.16 | `lib/pages/apps.dart:142-144` (and ~26 more) |
| 1.17 | `lib/main.dart:329-332` |
| 1.18 | `lib/providers/apps_provider.dart:1259-1263` |
| 1.19 | `lib/providers/apps_provider.dart:423-461` |
| 1.20 | `lib/providers/apps_provider_lifecycle.dart:132-135` |
| 1.21 | `lib/providers/apps_provider_updates.dart:260-270` |
| 1.22 | `lib/components/generated_form_renderer.dart:377-380,197-208` |
| 1.23 | `lib/pages/app.dart:189-193,124-136` |
| 1.24 | `lib/main.dart:117,122` |
| 1.25 | `lib/main.dart:354-355` |
| 1.26 | `lib/providers/logs_provider.dart:60-71` |

### Dead code

| Item | File:Line |
|---|---|
| `moveStrToEndMapEntryWithCount` | `lib/providers/apps_provider.dart:194-198` |
| `HighlightableButton` | `lib/components/ui_widgets.dart:158-205` |
| `GeneratedFormFieldState` | `lib/components/generated_form_model.dart:7-19` |
| `FormFieldDefinition` + `toGeneratedFormItem` | `lib/components/generated_form_model.dart:21-111` |
| `toDefinition` | `lib/components/generated_form_model.dart:130-189` |
| Empty `onDismissed` | `lib/components/app_list_tile.dart:536` |
| `_lastAppId` | `lib/components/app_list_tile.dart:144-150` |
| `webViewReady` getter | `lib/pages/app.dart:54` |
| `Jenkins.trimJobUrl` | `lib/app_sources/jenkins.dart:33` |
| RuStore dead null check | `lib/app_sources/rustore.dart:91-93` |

---

## Appendix B — Positive Observations

The codebase shows clear signs of careful engineering. Things done well that should be preserved:

- **Named constants block** at `apps_provider.dart:46-58` (`_defaultRetries`, `_retryDelaySeconds`, etc.) — good practice; the remaining magic numbers (§6) should follow this pattern.
- **`App.copyWith` with sentinel pattern** (`source_provider.dart:158-212`) — correctly handles nullable field updates.
- **`DownloadState` as `ValueNotifier`** (`apps_provider.dart:68-101`) — correctly avoids full Provider rebuilds on progress ticks. The comment explaining why is excellent.
- **`standardizeUrlWithRegex` helper** (`source_provider.dart:525-537`) — well-designed and used by 19 sources; a successful refactoring.
- **`rethrowOrWrapError`** (`custom_errors.dart:66-104`) — consistent error wrapping with stack trace capture (the boilerplate around it is the problem, not the function itself).
- **`TypedSettings` class** (`source_provider.dart:1205-1237`) — good step toward type-safe settings access (underutilized; §3.4).
- **Error classes in `custom_errors.dart`** — well-structured with codes, data, and localization via `localizeErrorCode`.
- **`withUrlContext` method** (`custom_errors.dart:52-59`) — elegant context attachment for logging.
- **Atomic write in `saveApps`** (`.tmp` + rename at `apps_provider_lifecycle.dart:423-425`) — correct crash-safe persistence.
- **FDroid changelog truncation handles UTF-16 surrogate pairs** (`fdroid.dart:151-159`) — subtle correctness detail.
- **Installer abstraction** (`lib/installers/installer.dart`) — clean `InstallResult` sealed-style result type, clear `Installer` contract with `wantsContainerHandoff` extension point.
- **`unawaited` usage** — consistently and correctly wrapped for fire-and-forget calls.
- **`onPopInvokedWithResult`** — all `PopScope` usages use the newer API (not the deprecated `onPopInvoked`).
- **Strong `const` usage** for leaf widgets (`const SizedBox`, `const Icon`, `const EdgeInsets`, `const CardTile`, `const Section`).
- **M3 Expressive theming** with dynamic color support and the `buildObtainiumTheme` helper.
- **Consistent use of `showError` / `showMessage` helpers** (`ui_widgets.dart:51`) across all 33 call sites.
- **`CancellationToken` pattern** for downloads — well-implemented.
- **Auto-export debouncing** (`apps_provider.dart:946-958`) with `_disposed` guard — correct.
- **`refreshProgress` as `ValueNotifier`** — the comment at `apps_provider.dart:837-841` explaining why is exactly the right instinct; the rest of the codebase should follow this pattern more broadly (§7).

---

*End of review.*
