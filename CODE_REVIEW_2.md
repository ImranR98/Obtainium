# Obtainium — Second-Pass Review: Bugfixes & Performance Improvements

**Scope:** Focused review of the post-refactor codebase for new bugs and performance issues not addressed in the first pass. Every item includes a `file:line` reference.

---

## Table of Contents

1. [Bugs](#1-bugs)
2. [Performance Improvements](#2-performance)
3. [First-Pass Regressions](#3-regressions)
4. [Suggested Phased Execution Plan](#4-phased-plan)

---

## 1. Bugs

### 1.1 [HIGH] First-run logic permanently skipped when prefs aren't loaded yet

**File:** `lib/main.dart:218-221`

In `_handleFirstRun`, if `settings.prefs == null` when the single post-frame callback fires, the method calls `settings.initializeSettings()` (without awaiting) and returns **before** setting `_firstRunHandled = true`. Since `_handleFirstRun` is only called once from `initState`'s post-frame callback, and no listener re-triggers it when settings become available, the notification permission request, auto-add of Obtainium, and locale validation are all skipped for that launch.

**Fix:** Await `settings.initializeSettings()` in `main()` before `runApp`, or remove the early `return` and restructure so first-run logic re-runs when settings become available.

### 1.2 [HIGH] LiteAPKs slug extraction is broken — source is non-functional

**File:** `lib/app_sources/liteapks.dart:64-70`

```dart
final slug = standardUri.path
    .split('.')
    .reversed
    .toList()
    .sublist(1)
    .reversed
    .join('.');
```

For `/my-app` (no extension): `split('.')` → `['/my-app']` → `sublist(1)` → `[]` → slug = `''`. The API call becomes `?slug=` which returns no results. For `/my-app.html`: slug = `/my-app` (with leading slash), which the WordPress API rejects.

**Fix:** `final slug = standardUri.pathSegments.last.split('.').first;`

### 1.3 [HIGH] HTML `filterApksByArch` on intermediate links can crash with StateError

**File:** `lib/app_sources/html.dart:356-359`

The emptiness check is done **before** `filterApksByArch` runs. If arch filtering removes all links (none match device ABIs), `intLinks` becomes empty and `intLinks.last` throws `StateError`.

**Fix:** Re-check emptiness after arch filtering:
```dart
if (intermediateLinks[i]['autoLinkFilterByArch'] == true) {
  intLinks = await filterApksByArch(intLinks);
}
if (intLinks.isEmpty) {
  throw NoReleasesError(note: currentUrl);
}
currentUrl = intLinks.last.key;
```

### 1.4 [HIGH] SourceForge off-by-one for `http://` URLs

**File:** `lib/app_sources/sourceforge.dart:27-29`

The magic offset `host.length + '/projects/'.length + 1` assumes `https://` (8 chars). For `http://` (7 chars), the project name loses its first character: `myproject` → `yproject`.

**Fix:** Use `Uri.parse` segments instead of string arithmetic.

### 1.5 [HIGH] ItchIO `parseUtc` throws on one bad date, killing entire app fetch

**File:** `lib/app_sources/itchio.dart:155-159`

`DateFormat.parseUtc` throws `FormatException` on any malformed date. If one `<abbr>` element has an unexpected `title` format, the entire fetch fails.

**Fix:** Use `tryParseUtc` and skip bad dates.

### 1.6 [HIGH] FDroidRepo `DateTime.parse` throws on malformed date

**File:** `lib/app_sources/fdroidrepo.dart:289-294`

`DateTime.parse` (not `tryParse`) throws if the `<added>` element contains a malformed date. Third-party F-Droid repos may have inconsistent formats.

**Fix:** Use `DateTime.tryParse`.

### 1.7 [HIGH] RuStore `downloadUrls` empty-list access throws RangeError

**File:** `lib/app_sources/rustore.dart:100`

`downloadDetails['downloadUrls']?[0]` — the `?` guards against null but not empty list. If the API returns `"downloadUrls": []`, `[0]` throws `RangeError`.

**Fix:** Check `isNotEmpty` before indexing.

### 1.8 [HIGH] LiteAPKs `versions[0]` on empty list throws RangeError

**File:** `lib/app_sources/liteapks.dart:99,104`

Same pattern as RuStore — `?[0]` guards null but not empty list.

**Fix:** Use `elementAtOrNull` or check `isNotEmpty`.

### 1.9 [HIGH] Escaped string interpolation in `_ThemeColorPickerTile`

**File:** `lib/pages/settings.dart:1139-1140`

```dart
subtitle: Text(
  '\${ColorTools.nameThatColor(settingsProvider.themeColor)} '
  '(\${ColorTools.materialNameAndCode(settingsProvider.themeColor)})',
),
```

The `\$` escapes prevent interpolation. The subtitle displays the literal text `${ColorTools.nameThatColor(...)}` instead of the actual color name.

**Fix:** Remove the backslashes.

### 1.10 [HIGH] WebView setState-after-dispose in `app.dart`

**File:** `lib/pages/app.dart:149-155,176-181`

`NavigationDelegate` callbacks call `setState` without `mounted` checks. The `WebViewController`/`NavigationDelegate` can outlive the State, so `onPageFinished` and `onWebResourceError` can fire after dispose.

**Fix:** Add `if (!mounted) return;` before each `setState` in WebView callbacks.

### 1.11 [HIGH] Deep link stream subscription leak in `home.dart`

**File:** `lib/pages/home.dart:290-304`

`initDeepLinks()` is `unawaited` from `initState`. The stream subscription is set at line 296 after two `await` calls. If the widget is disposed during those awaits, `dispose()` runs and calls `_linkSubscription?.cancel()` — but `_linkSubscription` is still `null`. When execution reaches line 296, the subscription is created but never cancelled.

**Fix:** Check `if (!mounted) return;` before creating the subscription.

### 1.12 [HIGH] External installer FGBG race — up to 2-hour hang on fast returns

**File:** `lib/installers/external_installer.dart:108-117`

The `returned` foreground subscription is set up **after** `wentAway` completes. If the external installer bounces back quickly (e.g., rejects the APK), the foreground event fires in the gap between `wentAway` completing and the `returned` subscription being created. That event is missed, and the code waits up to `_foregroundReturnFallback` (2 hours).

**Fix:** Subscribe to the foreground event **before** launching the intent.

### 1.13 [HIGH] External installer `firstWhere(...).timeout(...)` leaks stream subscriptions

**File:** `lib/installers/external_installer.dart:100-105,111-116`

`Future.timeout` does not cancel the underlying `firstWhere` subscription when `onTimeout` fires. When the background-detection window (30s) times out (modal installer path), the subscription stays active on the broadcast stream. Same for the 2-hour foreground timeout.

**Fix:** Manage subscriptions explicitly with a `Completer` + `Timer` and cancel on timeout.

### 1.14 [HIGH] `waitForPackageInstall` false-positive when `baseline.updateTime` is null

**File:** `lib/installers/install_utils.dart:25-30`

When `baseline.updateTime` is null (certain Android versions/ROMs), the condition `baseline.updateTime == null` is true on the first poll, so the function returns `true` immediately — regardless of whether the install actually happened. The harness then reports `InstallResult.success()` even if the user cancelled.

**Fix:** When `baseline.updateTime` is null, compare `versionCode` instead of short-circuiting to success. Requires `InstallBaseline` to capture `versionCode`.

### 1.15 [MEDIUM] Shizuku `ensurePermission` switch has no default — silent pass-through

**File:** `lib/installers/shizuku_installer.dart:27-37`

If `checkPermission()` returns `null` or an unexpected string (e.g., a future Shizuku version returns a new error code), the method silently returns without throwing, and the install proceeds without permission.

**Fix:** Add `default` case that throws, and explicitly match `granted_*` cases as no-ops.

### 1.16 [MEDIUM] `setState` after dispose in `apps.dart` `refresh()`

**File:** `lib/pages/apps.dart:244-246`

```dart
.whenComplete(() {
  setState(() {});  // no mounted check
});
```

**Fix:** Add `if (mounted)` guard.

### 1.17 [MEDIUM] `setState` after dispose in form post-frame callbacks

**File:** `lib/components/generated_form_renderer.dart:367-369,197`

Post-frame callbacks call `notifyFormChange` which calls `setState(() {})` without a `mounted` check.

**Fix:** Add `if (mounted)` guard in post-frame callbacks and/or in `notifyFormChange`.

### 1.18 [MEDIUM] GitLab search assumes `name_with_namespace` is always present

**File:** `lib/app_sources/gitlab.dart:86-89`

`element['name_with_namespace']` is used without a null check. If any project in search results is missing this field, inserting `null` into `Map<String, List<String>>` throws `TypeError`.

**Fix:** Add `?.toString() ?? ''` fallback.

### 1.19 [MEDIUM] GitLab `tag_name ?? name` can produce null version

**File:** `lib/app_sources/gitlab.dart:232`

`APKDetails`'s `version` is `String` (non-nullable). If both `tag_name` and `name` are null, this passes null and throws `TypeError`.

**Fix:** Check for null and throw `NoVersionError` or skip the release.

### 1.20 [MEDIUM] DirectAPKLink regex rejects `.apk` URLs with query strings

**File:** `lib/app_sources/direct_apk_link.dart:53`

The regex `.+\.apk$` requires the URL to end with `.apk`. CDN-served APKs with signed URLs (e.g., `app.apk?token=abc&expires=...`) are rejected.

**Fix:** `RegExp(r'.+\.apk([?#].*)?$', caseSensitive: false)`

### 1.21 [MEDIUM] FDroid no type check on JSON response

**File:** `lib/app_sources/fdroid.dart:233-234`

If `jsonDecode` returns a non-Map (e.g., a JSON array), `response['packages']` throws `NoSuchMethodError`.

**Fix:** `final response = jsonDecode(res.body); List<dynamic> releases = (response is Map) ? (response['packages'] ?? []) : [];`

### 1.22 [MEDIUM] `callbackDispatcher` logs before bindings are initialized

**File:** `lib/main.dart:69-93`

`callbackDispatcher` calls `await logs.add(...)` (line 73) before `bgUpdateCheck` calls `WidgetsFlutterBinding.ensureInitialized()`. `LogsProvider.add()` opens an sqflite database via method channels, which requires bindings. If the WorkManager isolate hasn't pre-initialized bindings, the first `logs.add()` throws. The catch block then calls `logs.add(...)` again — which also fails silently.

**Fix:** Add `WidgetsFlutterBinding.ensureInitialized();` as the first line of `callbackDispatcher`.

### 1.23 [MEDIUM] `MultiAppMultiError.add` doesn't remove appId from previous error group

**File:** `lib/custom_errors.dart:208-224`

If the same `appId` is added twice with different errors, `rawErrors[appId]` is overwritten but `idsByErrorString` is not cleaned up — the `appId` remains listed under the old error string's group. `toString()` displays the same app under two separate error headings.

**Fix:** Before inserting into the new group, remove `appId` from any existing group.

### 1.24 [MEDIUM] `rethrowOrWrapError` re-wraps unexpected ObtainiumError, losing original code

**File:** `lib/custom_errors.dart:85-93`

When an `ObtainiumError` with `unexpected: true` is passed in, the function creates a brand-new `ObtainiumError` with `code: 'UNEXPECTED'`, discarding the original error code (e.g., `'INSTALL_FAILED'`). If caught upstream and `rethrowOrWrapError` is called again, it logs a second time — duplicate log entries.

**Fix:** Preserve the original code, or simply re-throw the original unexpected error as-is.

### 1.25 [MEDIUM] VivoAppStore `/#` replacement breaks SPA URLs

**File:** `lib/app_sources/vivoappstore.dart:118-121`

For SPA URLs like `https://h5.appstore.vivo.com.cn/#appId=123` (where `#` is immediately followed by `appId` without `/`), `replaceFirst('/#', '')` produces a malformed URL.

**Fix:** Handle the fragment explicitly via `Uri.parse(url).fragment`.

### 1.26 [MEDIUM] APKMirror version extraction fragile with multiple " by " in title

**File:** `lib/app_sources/apkmirror.dart:126-134`

If the app name contains " by " (e.g., `App by Someone 1.2.3 by Developer`), `byMatches.last.start` points to the last " by ", producing a version like `by Someone 1.2.3`.

**Fix:** Use a regex to find the version string directly: `RegExp(r'(\d+\.\d+(?:\.\d+)*)').firstMatch(titleString)`.

### 1.27 [MEDIUM] NeutronCode `filename` not trimmed → malformed APK URL

**File:** `lib/app_sources/neutroncode.dart:72-85`

`filename` is extracted from `.innerHtml` without `.trim()`. Whitespace or HTML entities produce a malformed URL.

**Fix:** Add `.trim()`.

### 1.28 [MEDIUM] `_buildSourceSpecificForm` mutates form item values in place

**File:** `lib/pages/add_app.dart:509-529`

The method mutates `item.value` directly on items from `s.combinedAppSpecificSettingFormItems`. If the source returns cached list instances, mutations persist and cause stale values in subsequent form instances.

**Fix:** Clone the form items before mutating (use the existing `clone()` method).

### 1.29 [MEDIUM] `setAppLocale` never called in background isolate

**File:** `lib/custom_errors.dart:264-266`, `lib/utils/translation_loader.dart`

`setAppLocale()` is only called from `main.dart` (foreground). In the background isolate, `_appCurrentLocale` is always null, so `isEnglish()` returns false and `lowerCaseIfEnglish`/`currentLanguageCode` return wrong defaults. Notification/error text formatting differs between foreground and background.

**Fix:** Call `setAppLocale(controller.locale)` at the end of `TranslationLoader.load()`.

### 1.30 [MEDIUM] `loadSystemFont()` failure path never sets guard — repeated platform calls

**File:** `lib/utils/native_features.dart:15-22`, `lib/main.dart:335-337`

If `getFilePath()` returns null (some devices don't expose a system font path), `_systemFontLoaded` is never set to true. Every subsequent rebuild calls `AndroidSystemFont().getFilePath()` again — a platform-channel round-trip on every build.

**Fix:** Track the attempt (not just success) so failures aren't retried:
```dart
static bool _systemFontAttempted = false;
static Future<void> loadSystemFont() async {
  if (_systemFontAttempted) return;
  _systemFontAttempted = true;
  // ... rest of method
}
```

### 1.31 [LOW] APKPure `native_code` cast throws if API returns non-List

**File:** `lib/app_sources/apkpure.dart:88`

`?.cast<String>()` throws `NoSuchMethodError` if `native_code` is a string instead of a list.

**Fix:** `rawArch is List ? rawArch.map((a) => a.toString()).toList() : <String>[]`

### 1.32 [LOW] LiteAPKs `pathSegments.last` throws on path-less URL

**File:** `lib/app_sources/liteapks.dart:110`

If a `version_download_link` is a bare host URL, `pathSegments` is `['']` or empty, and `.last` throws `StateError`.

**Fix:** Filter empty segments first.

### 1.33 [LOW] `int.parse` in `compareAlphaNumeric` throws on very large numeric segments

**File:** `lib/utils/string_compare.dart:13-14`

Version strings with numeric segments longer than 18-19 digits (hash-like build numbers) cause `int.parse` to throw `FormatException` (overflow). Used in sort calls, so one malformed version crashes release sorting.

**Fix:** Wrap in try/catch falling back to string comparison, or use `BigInt.parse`.

### 1.34 [LOW] Installer code 3 mapped to `alreadyInstalled` but AOSP defines it as `STATUS_FAILURE_ABORTED`

**File:** `lib/installers/installer.dart:5-6,38-39`

Code 3 = `STATUS_FAILURE_ABORTED` (user cancelled). The `fromPlatformCode` factory maps this to `InstallOutcome.alreadyInstalled` instead of `InstallOutcome.cancelled`. Practical impact is nil today (both are treated identically downstream), but semantically incorrect.

**Fix:** Map code 3 to `cancelled`.

### 1.35 [LOW] `useBlackTheme` applies `.harmonized()` after setting surface to pure black

**File:** `lib/main.dart:329-333`

`ColorScheme.harmonized()` may shift pure black towards a dark tinted color, partially defeating the AMOLED "black theme" purpose.

**Fix:** Skip `.harmonized()` on the surface, or apply harmonization before overriding surface.

### 1.36 [LOW] `AppIconWidget` icon never updates after initial load

**File:** `lib/components/app_list_tile.dart:132-183`

`_iconFuture` is set in `initState` and used in a `FutureBuilder`. Once the future completes, the `FutureBuilder` never rebuilds. Stale icon bytes are displayed if the icon is updated later.

**Fix:** Use a `ListenableBuilder` that listens to the apps provider for icon changes, or trigger a rebuild when the icon updates.

### 1.37 [LOW] `AppFilePicker` radio `orElse` throws on empty list

**File:** `lib/components/app_detail_widgets.dart:134-137`

`orElse: () => urlsToSelectFrom.first` throws `StateError` if `urlsToSelectFrom` is empty. Unlikely in practice but defensive coding would guard it.

**Fix:** Guard with `isNotEmpty`.

---

## 2. Performance Improvements

### 2.1 [MEDIUM] `ColorScheme.fromSeed` recomputed on every rebuild

**File:** `lib/main.dart:318-326`

`build()` calls `context.watch<SettingsProvider>()`, so any settings change triggers a rebuild. `ColorScheme.fromSeed(...)` is called twice (light + dark) on every rebuild, running the full Material You seed-to-scheme algorithm. Most rebuilds are from unrelated settings (sort order, category edits).

**Fix:** Memoize the color schemes keyed by `(themeColor, colourSchemeMode, lightDynamic, darkDynamic)`. Use `Selector<SettingsProvider, (Color, ColourSchemeMode)>` to only rebuild when theme-relevant settings change.

### 2.2 [MEDIUM] ~25 regexes compiled per `getSource` call

**File:** `lib/providers/source_provider.dart:1049-1051`

Every call to `getSource(url)` compiles ~25 regexes (one per source) and calls `Uri.parse(url)` ~25 times. Source detection is called for every app addition and every batch import URL. The host patterns are static per source class.

**Fix:** Precompile a host-matching regex per source (lazily, on first use) and cache it as a field on `AppSource`. Call `Uri.parse(url)` once before the loop.

### 2.3 [MEDIUM] `filterApksByArch` regex compiled per-APK-per-ABI

**File:** `lib/providers/source_provider.dart:1654-1660`

`RegExp('.*$abi.*')` is constructed inside the `.where()` callback — compiled once per APK URL per ABI. For 20 APKs and 3 ABIs, that's 60 compilations.

**Fix:** Compile the regex once per ABI before the filter:
```dart
for (var abi in abis) {
  final abiRegex = RegExp('.*$abi.*', caseSensitive: false);
  final urls2 = apkUrls.where((e) => abiRegex.hasMatch(e.key)).toList();
  // ...
}
```

### 2.4 [MEDIUM] GitHub regex + list sort inside sort comparator (O(n log n) times)

**File:** `lib/app_sources/github.dart:467-478`

The sort comparator computes a set intersection, converts to a list and sorts it, and compiles a new `RegExp` — all inside the comparator. For 100 releases, that's ~700 regex compilations.

**Fix:** Precompute/memoize regexes by format string before the sort.

### 2.5 [MEDIUM] GitHub filter regexes recompiled per release in loop

**File:** `lib/app_sources/github.dart:540,544-546`

`RegExp(regexFilter)` and `RegExp(regexNotesFilter)` are recompiled on every loop iteration (up to 100 releases). The patterns are constant across iterations.

**Fix:** Compile once before the loop.

### 2.6 [MEDIUM] ItchIO page fetched twice (redundant HTTP request)

**File:** `lib/app_sources/itchio.dart:278,285-288`

The store page is fetched once to parse title/author/version, then `_setupDownload` fetches the same URL again to extract CSRF token and cookies. This doubles network latency.

**Fix:** Extract CSRF/cookies from the first response's headers and body.

### 2.7 [MEDIUM] GitLab regex compiled inside `.map()` per APK

**File:** `lib/app_sources/gitlab.dart:262-265`

`RegExp('^${RegExp.escape(standardUrl)}/-/jobs/...')` is constructed once per APK URL in the map callback.

**Fix:** Hoist the regex outside the map.

### 2.8 [MEDIUM] `jsonEncode` in `appSignature` called on every AppPage build

**File:** `lib/pages/app.dart:223` (called from `cachedApp` in `build()`)

`jsonEncode(app.additionalSettings)` runs on every AppPage rebuild. `jsonEncode` is relatively expensive.

**Fix:** Replace with a cheaper hash: `Object.hashAll(app.additionalSettings.entries.map((e) => Object.hash(e.key, e.value)))`.

### 2.9 [MEDIUM] `RegExp` created inside loop on every build in `SelectionModal`

**File:** `lib/pages/import_export.dart:794,802-805`

`RegExp(filterRegex)` is constructed inside `entrySelections.forEach(...)` — once per entry per build. With 100 entries and an active filter, this creates 100 `RegExp` objects on every rebuild.

**Fix:** Hoist the `RegExp` creation above the loop.

### 2.10 [MEDIUM] `DateFormat` constructed on every tile build

**File:** `lib/components/app_list_tile.dart:962`

`DateFormat('yyyy-MM-dd')` is created inside `changesLabel()`, called for every visible tile on every rebuild. Construction involves locale lookup and pattern parsing.

**Fix:** Cache as a static field: `static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');`

### 2.11 [MEDIUM] `ValueListenableBuilder` not using `child` parameter in `AppListTile`

**File:** `lib/components/app_list_tile.dart:377-379`

The entire tile (Semantics, Container, gradient, ListTile, leading icon, title, subtitle, trailing) is rebuilt inside the `builder` callback on every download progress tick. The `child` parameter is available but not used.

**Fix:** Extract parts that don't depend on `downloadProgress` into the `child` parameter. Only rebuild the `trailing` widget inside `builder`.

### 2.12 [MEDIUM] HTML redundant JSON parse attempt on HTML body

**File:** `lib/app_sources/html.dart:81-104`

When `matchLinksOutsideATags` is true and the body is HTML (not JSON), the code: (1) parses the full HTML DOM, (2) attempts `jsonDecode` on the entire body (which fails), (3) falls back to `getLinksInLines(rawBody)`. The HTML-parsed links from step 1 are discarded. The JSON decode attempt on HTML is wasted work.

**Fix:** When `allLinks` is already non-empty, skip the JSON path and go directly to regex scanning.

### 2.13 [LOW] `CategoryManager` uses `context.watch` instead of `context.select`

**File:** `lib/components/category_editor.dart:508`

Watches entire `SettingsProvider` but only uses `categories`. Any settings change rebuilds the category manager.

**Fix:** `context.select<SettingsProvider, Map<String, int>>((p) => p.categories)`

### 2.14 [LOW] Extracted settings tiles use `context.watch` for narrow access

**File:** `lib/pages/settings.dart:1128,1168,1212,1240`

`_ThemeColorPickerTile`, `_ThemeModeSegmentedButton`, `_LocaleDropdown`, `_ColourSchemeDropdown` each use `context.watch<SettingsProvider>()` but only access one or two fields. Each settings change rebuilds all of them.

**Fix:** Replace each with `context.select` for the specific field(s) used.

### 2.15 [LOW] `_ExternalInstallerTile` uses `context.watch` for narrow field access

**File:** `lib/pages/settings.dart:1071`

Watches entire `SettingsProvider` but only uses `externalInstallerPackage` and `externalInstallerComponent`.

**Fix:** Use `context.select` for the specific fields.

### 2.16 [LOW] Redundant post-frame callbacks scheduled from `build()` in `apps.dart`

**File:** `lib/pages/apps.dart:1100-1115`

When `localSelected.length != selectedAppIds.length`, a `addPostFrameCallback` is scheduled from `build()`. If `build()` runs multiple times before the callback fires, redundant callbacks are scheduled.

**Fix:** Use a flag (`bool _selectionPruneScheduled = false;`) to ensure only one callback is scheduled at a time.

### 2.17 [LOW] `Theme.of(context)` called multiple times without caching

**File:** `lib/pages/app.dart:1016-1049` (5 calls in `_buildSourceInfoSections`), `lib/pages/app.dart:1271,1312,1315` (3 calls in `build()`)

**Fix:** Cache `final theme = Theme.of(context);` at the top of each method.

### 2.18 [LOW] `supportedLocales.map(...).contains(...)` allocates and iterates on every launch

**File:** `lib/main.dart:264`

Builds a 30-element `Iterable` and linear-scans it on every app launch.

**Fix:** Precompute a `Set`: `final supportedLocaleSet = supportedLocales.map((e) => e.key).toSet();`

### 2.19 [LOW] Unnecessary `Future.delayed` after final poll attempt

**File:** `lib/installers/install_utils.dart:22-33`

On the final attempt, the 500ms delay runs before the loop exits and returns false. Adds 500ms to every failed detection.

**Fix:** Guard the delay with `attempt < attempts - 1`.

### 2.20 [LOW] `Random()` allocated on every `generateRandomLightColor` call

**File:** `lib/utils/color_utils.dart:7`

`Random().nextInt(120)` constructs a fresh `Random` on every invocation.

**Fix:** Use a single reused `Random` instance.

### 2.21 [LOW] `listSync` on UI thread in `loadApps` and `removeApps`

**File:** `lib/providers/apps_provider_lifecycle.dart:235` (`getAppsDir().listSync()`), `:450` (`apkDir.listSync()`), `lib/providers/apps_provider_install.dart:260` (`.listSync(recursive: true)`), `:487` (`.listSync(recursive: true, followLinks: false)`)

Sync directory listing on the UI thread. Fine for small directories but should be async for safety as cache grows.

**Fix:** Use `dir.list()` (returns `Stream`) with `await for` or `.toList()`.

### 2.22 [LOW] `filterApksByArch` `preferSplits` parameter is unused

**File:** `lib/providers/source_provider.dart:1650`

The `preferSplits` parameter is declared but never referenced in the function body. Misleading — callers pass `preferSplits: true` but it has no effect.

**Fix:** Either implement split-APK preference logic or remove the parameter and update callers.

---

## 3. First-Pass Regressions

These are issues introduced or not fully fixed by the first refactoring pass.

### 3.1 [HIGH] `doStringsMatchUnderRegEx` with empty pattern returns true — hides pending updates

**File:** `lib/providers/apps_provider_updates.dart:260-265`

The first pass changed `findAppIdsWithPendingUpdates` to use `doStringsMatchUnderRegEx` instead of string `!=`. But when `versionExtractionRegEx` is empty/null (the default for most apps), `doStringsMatchUnderRegEx('', installed, latest)` compiles `RegExp('')` which matches everything with a zero-length match. The comparison `value1.substring(0,0) == value2.substring(0,0)` → `"" == ""` → true. So all versions "match", and no apps are reported as having pending updates. This is a **regression** — the old `!=` comparison would correctly report different versions as pending.

**Fix:** When the pattern is empty, fall back to simple `==` comparison:
```dart
bool versionsMatch(String pattern, String v1, String v2) {
  if (pattern.isEmpty) return v1 == v2;
  return doStringsMatchUnderRegEx(pattern, v1, v2);
}
```

### 3.2 [MEDIUM] `SourceProvider.getSource` still catches all exceptions, not just `ObtainiumError`

**File:** `lib/providers/source_provider.dart:1055-1057,1069-1071`

The first pass was supposed to narrow the catch to `ObtainiumError` only, but the code still has `catch (e)` which swallows all exceptions including `StateError`, `RangeError`, etc.

**Fix:** Change `catch (e)` to `on ObtainiumError catch (e)`.

### 3.3 [MEDIUM] Optimistic `installedVersion = latestVersion` still set before install confirmation

**File:** `lib/providers/apps_provider_install.dart:630-635`

The first pass was supposed to defer this until after install confirmation, but the `needsBGWorkaround` branch still sets `installedVersion: latestVersion` before the install call.

**Note:** This is intentional for the BG workaround (the `await installApk` never returns in BG). The comment explains this. A proper fix requires platform API changes. Leave as-is but add a more prominent warning comment.

### 3.4 [LOW] `native_features.dart` — `_fontLoaded` guard was removed but now `loadSystemFont` is called on every build

**File:** `lib/main.dart:335-337`

The first pass removed the `_fontLoaded` guard to allow font reload on toggle. But now `loadSystemFont()` is called on **every rebuild** (not just when the setting changes). While `loadSystemFont` has an internal `_systemFontLoaded` guard, the platform-channel call to `getFilePath()` still happens on every build when the font path was null.

**Fix:** This is addressed by fix 1.30 above (track the attempt, not just success).

---

## 4. Suggested Phased Execution Plan

### Phase A — Critical bugfixes (high severity)

1. **Fix first-run prefs race** (§1.1) — await settings init in `main()`
2. **Fix LiteAPKs slug extraction** (§1.2) — source is non-functional
3. **Fix HTML `filterApksByArch` crash** (§1.3) — re-check emptiness after arch filter
4. **Fix SourceForge `http://` off-by-one** (§1.4) — use Uri segments
5. **Fix ItchIO `parseUtc` crash** (§1.5) — use `tryParseUtc`
6. **Fix FDroidRepo `DateTime.parse` crash** (§1.6) — use `tryParse`
7. **Fix RuStore empty-list RangeError** (§1.7) — check `isNotEmpty`
8. **Fix LiteAPKs empty-list RangeError** (§1.8) — check `isNotEmpty`
9. **Fix escaped string interpolation** (§1.9) — remove backslashes in settings.dart
10. **Fix WebView setState-after-dispose** (§1.10) — add `mounted` guards
11. **Fix deep link subscription leak** (§1.11) — check `mounted` before subscribing
12. **Fix external installer FGBG race** (§1.12) — subscribe to foreground before launch
13. **Fix external installer subscription leak** (§1.13) — cancel on timeout
14. **Fix `waitForPackageInstall` false-positive** (§1.14) — compare versionCode when updateTime is null
15. **Fix `doStringsMatchUnderRegEx` empty-pattern regression** (§3.1) — fall back to `==` for empty pattern

### Phase B — Medium-severity bugfixes

1. **Fix Shizuku missing default case** (§1.15)
2. **Fix `setState` after dispose in `apps.dart` refresh** (§1.16)
3. **Fix `setState` after dispose in form post-frame callbacks** (§1.17)
4. **Fix GitLab search null fields** (§1.18)
5. **Fix GitLab null version** (§1.19)
6. **Fix DirectAPKLink query-string regex** (§1.20)
7. **Fix FDroid JSON type check** (§1.21)
8. **Fix `callbackDispatcher` bindings init** (§1.22)
9. **Fix `MultiAppMultiError` stale groups** (§1.23)
10. **Fix `rethrowOrWrapError` code loss** (§1.24)
11. **Fix VivoAppStore SPA URL parsing** (§1.25)
12. **Fix APKMirror version extraction** (§1.26)
13. **Fix NeutronCode filename trim** (§1.27)
14. **Fix form item mutation** (§1.28) — clone before mutating
15. **Fix background isolate locale** (§1.29) — call `setAppLocale` in `TranslationLoader.load()`
16. **Fix `loadSystemFont` retry loop** (§1.30) — track attempt
17. **Narrow `SourceProvider.getSource` catch** (§3.2) — `on ObtainiumError catch (e)`

### Phase C — Low-severity bugfixes

1. **Fix APKPure `native_code` cast** (§1.31)
2. **Fix LiteAPKs path-less URL** (§1.32)
3. **Fix `int.parse` overflow in `compareAlphaNumeric`** (§1.33)
4. **Fix installer code 3 mapping** (§1.34)
5. **Fix `useBlackTheme` harmonization** (§1.35)
6. **Fix `AppIconWidget` stale icon** (§1.36)
7. **Fix `AppFilePicker` empty-list guard** (§1.37)

### Phase D — Performance improvements

1. **Memoize `ColorScheme.fromSeed`** (§2.1) — cache keyed by theme inputs
2. **Precompile source host-matching regexes** (§2.2) — cache on `AppSource`
3. **Fix `filterApksByArch` regex compilation** (§2.3) — compile once per ABI
4. **Fix GitHub sort comparator regex** (§2.4) — memoize by format string
5. **Fix GitHub filter regex recompilation** (§2.5) — compile before loop
6. **Fix ItchIO redundant HTTP request** (§2.6) — reuse first response
7. **Fix GitLab regex in `.map()`** (§2.7) — hoist outside map
8. **Fix `appSignature` `jsonEncode`** (§2.8) — use cheaper hash
9. **Fix `SelectionModal` regex in loop** (§2.9) — hoist above loop
10. **Cache `DateFormat` in `AppListTile`** (§2.10) — static field
11. **Use `child` in `ValueListenableBuilder`** (§2.11) — extract static parts
12. **Fix HTML redundant JSON parse** (§2.12) — skip when links already found
13. **Switch `CategoryManager` to `context.select`** (§2.13)
14. **Switch settings tiles to `context.select`** (§2.14)
15. **Switch `_ExternalInstallerTile` to `context.select`** (§2.15)
16. **Guard redundant post-frame callbacks** (§2.16) — use flag
17. **Cache `Theme.of(context)` in `app.dart`** (§2.17)
18. **Precompute `supportedLocaleSet`** (§2.18)
19. **Remove unnecessary `Future.delayed` on final poll** (§2.19)
20. **Reuse `Random` instance** (§2.20)
21. **Convert `listSync` to `list` (async)** (§2.21)
22. **Remove or implement `preferSplits` parameter** (§2.22)

---

## Appendix — Files With No New Issues

- `lib/installers/stock_installer.dart` — clean
- `lib/main_fdroid.dart` — clean
- `lib/theme.dart` — clean
- `lib/utils/format_utils.dart` — clean
- `lib/utils/string_utils.dart` — clean
- `lib/utils/nav_helper.dart` — clean
- `lib/providers/app_json_migration.dart` — clean

---

*End of second-pass review.*
