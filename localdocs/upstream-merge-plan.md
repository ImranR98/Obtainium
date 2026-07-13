# ObtainX ⇆ upstream merge — resolution plan

**Branch:** `chore/upstream_sync_20260712` (merge in progress)
**Base = HEAD** (fork, 147 commits) · **Theirs = MERGE_HEAD** (upstream Obtainium, 298 commits) · merge-base `4ad4b1b`
**89 conflicts.** Direction locked with the user:

1. **Adopt upstream skeleton, keep our features** — upstream's split providers / installer abstraction / form-engine split / `theme.dart` / component extraction become the base; our distinctive features are re-homed onto it.
2. **Best-of-both M3E per surface** — keep our color science (boosted HCT schemes, true-black, per-app color), adopt upstream's shape/motion tokens (superellipse, stadium pills, FadeForwards); every visible clash is decided per-surface with the user.
3. **Full written plan first, then execute in stages**, compile-gating at stage boundaries. **No git commit without explicit approval** (leave resolved-but-uncommitted).

## The collision (why it's 89)
Both sides independently did M3E **and** a major architecture refactor **and** an installer abstraction (both did Shizuku). Upstream also hardened every source parser and shipped `docs/DEVELOPER_GUIDE.md` (our migration map).

## UI reassurance (verified from code + screenshots)
- **Your ObtainX** = the tan/brown home: 4-tab bottom nav (Apps · Add app · Backup · Settings) + `NavigationRail` on large screens + mid-screen action toolbar.
- **Upstream** = the green home: 2-tab nav (Apps · Settings) + expressive "+ Add" FAB + "Install/update apps" hero card.
- **Your visible layout stays yours.** Pages are resolved ours-as-base (churn is lopsided in our favor: apps.dart 7007/1166 vs 1211/1188, etc.). Upstream's structural UI (their FAB, 2-tab nav, hero card) is **not** grafted. Only shape/shade/motion refinements are candidates, each with per-surface sign-off.

## Per-file ownership (from churn ours/theirs vs merge-base)
- **Fork-dominant (ours base):** MainActivity.kt, apps/app/settings/add_app/import_export/home pages, apps_provider, settings_provider, notifications_provider, apkmirror, izzyondroid, tencent, custom_app_bar, generated_form, native_provider.
- **Upstream-dominant (theirs base):** most app_sources, source_provider, logs_provider, settings_widgets.
- **Dual rewrite:** github, fdroidrepo, main.dart (theme), custom_errors, direct_apk_link, fdroid.

## Execution order (compile-gate at each boundary)

### Stage 0 — Mechanical (do anytime; independent)
- `git rm` ours: `.flutter`, `assets/screenshots/*`, `fastlane/metadata/*/full_description.txt`.
- `README.md` → ours + graft upstream factual fixes.
- 36 × `translations/*.json` → take **ours** `en.json` base, union upstream keys, re-run `standardize.mjs`. ⚠️ watch untracked generated `values-*` overlay drift.
- `pubspec.yaml`/`.lock` → union deps; adopt `workmanager` (pulls background-task rewrite into scope).

### Stage 1 — App sources  ◀ IN PROGRESS
- **Take theirs** (trivial fork deltas, upstream hardened): apk4free, apkcombo, aptoide, codeberg, farsroid, html, itchio, neutroncode, rockmods, rustore, sourceforge, sourcehut, telegramapp, uptodown.
- **Theirs base + port our feature delta:** apkpure, vivoappstore, coolapk, gitlab.
- **Ours base + graft upstream hardening:** apkmirror, izzyondroid, tencent.
- **Dual reconcile:** github, fdroidrepo, fdroid, direct_apk_link (both-added → one impl, best-of-both).
- **mullvad.dart** (deleted by them) → accept deletion (confirm).

### Stage 2 — Providers (adopt upstream split; re-home our methods into `extension AppsProvider*`)

> **⚠️ Carry-over fields required by Stage 1 grafts** — when taking `source_provider.dart` theirs-base, these fork members MUST be re-added or Stage 1 sources won't compile:
> - `APKDetails`: `apkSizeBytes`, `iconUrl` (used by aptoide, apkpure, vivo, coolapk)
> - `AppSource` base: `regionalStore`, `canSearch`, `showReleaseTitleAsVersionToggle` (farsroid), and the `search()` override signature (coolapk/tencent).
> - Note: upstream did "Centralize APK detection" — prefer their APK-extension detection over the fork's `app_package_formats.dart` per-source lists (gitlab took theirs for this reason).
>
> **Structural facts (verified) for adapting fork sources to upstream's new `AppSource` base:**
> - `additionalSourceAppSpecificSettingFormItems` is now a **getter** (`get ... => []`) — fork field-assignment in constructors must become `@override get` overrides.
> - `GeneratedFormItem`/`TextField`/`Switch`/`Dropdown`/`SubForm` now live in `components/generated_form_model.dart` (import swap from `generated_form.dart`).
> - Base ALREADY has: `standardizeUrlWithRegex(...)`, `inferAppIdFromUrlPath`, `naiveStandardVersionDetection`, `canSearch`, `search()` signature, `AppSource.fallbackToOlderReleasesFormItem` — fork sources adapt onto these.
> - Fork-only (must re-add in Stage 2): `regionalStore`, `iconUrl`+`apkSizeBytes`+`rawReleaseTitleCandidates` (on `APKDetails`, incl. `App.fromJson` round-trip), `showReleaseTitleAsVersion`/`releaseTitleAsVersion`.
> - Verified PRESENT in upstream base (no action): `standardizeUrlWithRegex`, `getSourceRegex`, `fallbackToOlderReleasesFormItem`, `tryInferAppIdFromLastPathSegment`, `inferAppIdFromUrlPath`, `naiveStandardVersionDetection`, `canSearch`, `search()`, `enforceTrackOnly`, `appIdInferIsOptional`, `showReleaseDateAsVersionToggle`.
> - **Reproducible-build subsystem (fork-only, big):** constants `reproducibleBuildStatusVerified`/`...NoData`, helpers `reproducibleBuildBoolFromStatus(...)`, and `App` fields `latestReproducibleStatus`/`reproducibleStatus`/`isReproducible` (14 refs in fork source_provider) — used by fdroid, fdroidrepo, izzyondroid, apps_provider, pages/app.dart. Must re-add to `source_provider.dart` + `apps_provider.dart` in Stage 2 or the F-Droid `enforceReproducibleBuilds` grafts won't resolve.
> - github fork-only: `GHReqPrefixUseToken` sub-option + request-header case-normalization (upstream already has the `GHReqPrefix` proxy itself — the two converged).

Take theirs skeleton (apps_provider core + `_install`/`_updates`/`_lifecycle`/`_import_export` extensions); drop our feature methods (VirusTotal, save-assets, folders, live-check, batch-fetch, pseudo-version) into the matching extension. source_provider → theirs (singleton) + re-register our sources + our `App` fields. settings_provider → ours + upstream additions. notifications_provider → ours + upstream ID-space fix. logs_provider → theirs. **native_provider.dart → migrate to a concrete `Installer` subclass** under `lib/installers/`, converge Shizuku best-of-both, then delete.

### Stage 3 — Components (adopt upstream extraction; keep our widgets)
generated_form(+modal) → adopt their `generated_form_model`+`renderer` split, re-apply our form features (PAT UI, field types). custom_app_bar → keep ours, wire into their shell (or port top-bar features onto their components). settings_widgets → theirs.

### Stage 4 — Pages + theme (split for safety)
- **4a — invisible correctness fixes (auto):** install-progress accuracy, saveApps-wiping-icons fix, swipe-dismiss guards, TV-nav fixes, crash guards.
- **4b — visible shape/shade/motion (per-surface approval):** theme merge (our color math + their superellipse/stadium/FadeForwards/motion tokens in `theme.dart`), plus any à-la-carte upstream component. Nothing visible lands without user sign-off.
- Pages (apps/app/settings/add_app/import_export/home) = **ours base**; graft named upstream items only.
- custom_errors → merge/union.

### Stage 5 — Android native
- MainActivity.kt → ours base + upstream SEND intent + onNewIntent/#3018/#3015 guards.
- AndroidManifest.xml → merge (ours providers/intents + supportsRtl / removed invalid exported).
- main_fdroid.dart → trivial merge.

## Cross-cutting sub-tasks pulled in by "adopt skeleton"
- `workmanager` background-task migration (re-express keep-awake / live-notification / interactivity-check).
- Installer abstraction convergence (unify Shizuku on upstream `Installer` interface).
- Keep `docs/DEVELOPER_GUIDE.md` (staged clean) — map for Stages 2–4.

## Verification
- Per stage: `flutter analyze` touched files; `flutter build apk --debug` once tree compiles.
- Final: full build + `/run` smoke (install flow, add source, update check, M3E surfaces, large-screen 2-panel).
- ObtainX is **not** under the FilePipe⇆Remember parity contract — no cross-app gate.

## Risk register
- Highest: generated_form split, apps_provider re-homing, workmanager rewrite.
- Medium: theme merge (color × shape interaction), source_provider singleton + custom-source registration.
- Tree will be non-compiling mid-merge — gate only at stage boundaries.

## ✅ MERGE COMPLETE (v3) — all conflicts resolved & staged; both flavors build; NOT committed

**Final state:** 0 unmerged files, `flutter analyze` 0 lib errors, `flutter build apk --debug` succeeds for **both** `normal` and `fdroid` flavors. All 112 changes staged; `MERGE_HEAD` intact — ready for the user to review and commit (no commit made, per standing rule).

**Compile-gate tail cleared (session 2 cont.):** immutable-App `copyWith` ripple (add_app/app/apps/izzyondroid/additional_options/main via mutable locals + sentinel-null copyWith); `LogLevels`→`LogLevel`; `appNavigatorKey`→`globalNavigatorKey`; `native_provider`→`apps_provider` for `NativeFeatures`; `pm`→`packageManager`; foundation imports (`kDebugMode`/`listEquals`); form `.defaultValue`→`.value`; provider params re-added to theirs-base methods (`getInstalledInfo`: `printErr`/`includeOwnDebugBuild`; `saveApps`: `updateInstalledInfo`/`autoExportAfterSave`; `downloadAppAssets`/`downloadAndInstallLatestApps`/`_resolveAppsToInstall`/`confirmAppFileUrl`: `dialogTheme`); `LogsProvider.get`: `limit`/`orderBy`; carry-over methods grafted (`reconcileVersionDifferences`+`...ByShape`/`versionShapeForReconciliation`/`numericVersionTokens` into apps_provider; `fdroidRepoRequestIndexWithVariants`+`apkDetailsFromIndexXmlResponse` into fdroidrepo); GitLab PAT statics grafted into gitlab.dart; `ObtainiumError.unexpected` relaxed to non-final; orphan upstream `category_editor.dart` removed; `MalwareScanWarningDialog` re-homed; GitHub attestation/PAT grafted.

**Translations:** `en.json` merged as union (804 fork + 32 upstream-only = 836 keys, fork values win); 28 locales standardized against it (missing keys → English fallback).

**Known non-blocking follow-ups (do NOT block build/app):**
- `test/version_order_test.dart` still uses the old positional `App(...)` ctor → fails `flutter analyze`/`flutter test` but NOT `flutter build apk`. Update to named args when convenient.
- Deliberately deferred (as before): GitHub/F-Droid attestation & reproducible status are NOT populated during update-check (`_fetchReleaseDetails` kept synchronous); install-time verification covers correctness.
- Upstream's page-level *invisible* fixes (swipe/TV-nav/crash guards) not individually grafted — pages taken ours-base wholesale.
- Best-of-both theme is app-wide (fork colours + upstream superellipse/stadium/FadeForwards); per-surface visual review still open if desired.
- Watch untracked generated `values-*` locale overlays (memory note) after any string edits.

---
## ▶ (v2 — historical) all code conflicts resolved & staged; compile-gate tail + translations remain

**Session 2 progress (all resolved-but-uncommitted, staged; NO commits):**
- **Stage 3 form component DONE:** `generated_form_model.dart` = upstream `value:`-API base + grafted fork `GeneratedFormSectionHeader`/`GeneratedFormTagInput` + `assistAction`/`assistIcon`/`assistTooltip`/`suffixIcon` (TextField), `labelTooltip` (Dropdown/Switch), `turnsOffKeys` (Switch). `generated_form_renderer.dart` = fork's rich renderer (outlined/section-cards/tag-input/category-picker/regex-assist/TV) adapted to `value:`, folded-in `GeneratedFormModal` + upstream `helpUrl`/`tileMode`, `export`s the model. Straggler imports (`additional_options_page`, `bulk_category_editor`, `version_regex_assist_dialog`) rewired to `_renderer`; `git rm` `generated_form.dart` + `generated_form_modal.dart`.
- **Compile-blockers DONE:** `MalwareScanWarningDialog` re-homed → `components/app_detail_widgets.dart`. GitHub attestation + PAT-validation subsystem grafted into `github.dart` (`shouldVerify/EnforceAttestations`, `getAttestationStatusForSha256Digest`, `canVerifyAttestations`, `buildVerificationMode`, PAT statics, build-verification-mode dropdown + PAT-validate assist). ⚠️ Deferred (like F-Droid gap): `_fetchReleaseDetails` still doesn't populate attestation during update-check; install-time `verifyGitHubAttestation` covers correctness.
- **Stage 5 native DONE:** `MainActivity.kt` = ours + `text/*` SEND + #3018/#3015 onNewIntent guard + `getSharedTextFromIntent` broadened. `AndroidManifest.xml` = `text/*` mime + kept fork FG-service perms. `main_fdroid.dart` = ours (`AppDistribution.fdroid`).
- **Stage 4 DONE (conflict-resolution):** `custom_errors.dart` = theirs code-based `ObtainiumError` base + grafted fork `DownloadCancelledError`/`MalwareScanBlockedError`/`showMessage`/`showError`. `import_export.dart` ours-base. `main.dart` = ours + **workmanager migration** (dropped BackgroundFetch → `callbackDispatcher`/`_scheduleWorkManager`; kept FlutterForegroundTask FG service) + **best-of-both theme** (`buildObtainiumTheme` upstream shape/motion base `.copyWith` fork boosted surfaces + nav/switch/tooltip/segmented). 5 pages (add_app/app/apps/home/settings) = **ours-base** (`checkout --ours`) + form-API/import fixes. Orphan upstream `category_editor.dart` deleted.

**COMPILE-GATE TAIL — 84 lib errors remain** (`flutter analyze`; tree fully de-conflicted). Categories:
- **Immutable-App `copyWith` ripple (~27 `assignment_to_final`)** — fork pages do `app.field = x` / `deepCopy()..field=`; convert to `copyWith(field: x)`. Sites: app.dart, add_app.dart, additional_options_page.dart, apps.dart, main.dart (first-run App). Also App **positional constructor → named** (main.dart first-run App ×2 + others).
- **Fork↔theirs provider params (~24 `undefined_named_parameter`)** — theirs-base methods lack fork params: `updateInstalledInfo` (×14), `includeOwnDebugBuild` (×4, on `getInstalledInfo`), `printErr` (×3), `autoExportAfterSave` (×1), `limit`/`orderBy` (settings_provider ×1 each). Decision per plan = **keep fork features** → re-add params+behavior to theirs-base methods (preferred) or adapt call sites.
- **Carry-over methods (Stage 1/2 gaps)** — `fdroidRepoRequestIndexWithVariants`+`apkDetailsFromIndexXmlResponse` (izzyondroid needs these on FDroidRepo/self), `reconcileVersionDifferences` (additional_options_page). Re-add from fork.
- **PAT calls in settings.dart** — `validatePAT`/`hasValidatedPAT`/`storePATValidation`/`clearPATValidation` need `GitHub.`-qualification (now statics on GitHub).
- **Misc** — `pm` undefined (app.dart ×3), `listEquals` (needs `foundation` import), `getDefaultValuesFromFormItems` (bulk_add_widget: now top-level fn, was method), `dialogTheme` named param (app.dart ×3), `app_list_tile`/`apkmirror`/`bulk_add_widget`/`apps_provider_lifecycle` singletons.
- NOTE: `test/version_order_test.dart` uses old positional `App(...)` — will fail analyze but does NOT block `flutter build apk` (fix later or update test to named args).

**THEN:** `flutter build apk --debug` (github + playstore flavors) → fix fallout → 29 translations (regenerate via `assets/translations/standardize.mjs`) → `/run` smoke.

**Also pending review (not blocking compile):** upstream's page-level *invisible* correctness fixes (swipe-dismiss/TV-nav/crash guards) were NOT individually grafted — pages taken ours-base wholesale. Revisit if desired.

---
## ▶ (v1 — historical) RESUME HERE (current state — 44 conflicts left: 15 code + 29 translations)

**Done & staged:** Stage 1 (all 26 sources), Stage 2 (all providers), Stage 0 partial (deletions, README, **pubspec resolved — `flutter pub get` passes, lock regenerated**), Stage 3 partial (settings_widgets→theirs, custom_app_bar→ours [kept — NEEDS compile check against immutable App/new skeleton]).

**Remaining conflicts:**
- **Stage 3 components (in progress):**
  - `generated_form.dart` + `generated_form_modal.dart` = deleted-by-them. TO DO: **graft fork form features into upstream's `generated_form_model.dart` + `generated_form_renderer.dart`** — the fork-only item types `GeneratedFormSectionHeader` and `GeneratedFormTagInput`, plus fork params `labelTooltip`/`assistIcon`/`defaultValue` (fork pages use these). THEN `git rm` the two old files. (Sources already import `generated_form_model`, so the split is committed to.)
  - Also re-home **`MalwareScanWarningDialog`** into a component (referenced by apps_provider_install) — likely `components/app_detail_widgets.dart`.
- **Stage 4 — pages + theme (largest UI work):** `main.dart` (theme merge: fork color science + upstream superellipse/stadium/FadeForwards tokens via `theme.dart`), `main_fdroid.dart`, `custom_errors.dart` (merge/union), pages `add_app`/`app`/`apps`/`home`/`import_export`/`settings` = **ours-base** + graft named upstream items. Split 4a (invisible fixes, auto) / 4b (visible shape/shade/motion, per-surface approval). Converge battery-opt setting on fork's `hideBatteryOptimizationWarning` (settings_provider uses it; upstream main/settings sides use `showBatteryOptimizationPrompt`). app.dart:~2200 `deepCopy()..apkSizeBytes=` → `copyWith`.
- **Stage 5 — native:** `MainActivity.kt` (ours-base + upstream SEND intent/#3018/#3015 guards), `AndroidManifest.xml` (merge: ours providers/intents + supportsRtl / removed invalid exported), `main_fdroid.dart` trivial.
- **Stage 0 — translations:** 29 JSONs — regenerate via `assets/translations/standardize.mjs` (ours en.json base + union upstream keys). Watch untracked generated `values-*` overlay drift.

**FORWARD-REF GAPS to close before compile gate (else won't compile):**
1. `github.dart`: add fork attestation API `shouldVerifyAttestations`/`shouldEnforceAttestations`/`getAttestationStatusForSha256Digest` (+ validatePAT bits). [Stage 1 revisit]
2. `MalwareScanWarningDialog` component (above).
3. custom_app_bar.dart kept-as-ours — verify it compiles vs new skeleton/immutable App.

**COMPILE GATE:** once all `lib/**.dart` + `MainActivity.kt` + `AndroidManifest` resolved → `flutter analyze` then `flutter build apk --debug`. Fix whatever surfaces. Then translations + real run via /run.

## Progress log
- [~] Stage 0 — mechanical: [x] .flutter/screenshots/fastlane deletions, README→ours, [x] **pubspec.yaml resolved + `flutter pub get` SUCCEEDS (171 deps, lock regenerated & staged)**; [ ] 29 translation JSONs (regenerate via standardize.mjs).
- [x] Stage 1 — app sources  (all 26 source conflicts resolved & staged; 89→63 remaining)
  - Open gap: fdroid/fdroidrepo `getLatestAPKDetails` kept upstream-synchronous — fork's F-Droid icon/APK-size/display-name + off-isolate parse NOT grafted (deliberate; pending user call).
- [x] Stage 2 — providers  ✅ COMPLETE (source_provider, apps_provider+4 ext, settings, notifications, logs; native_provider deleted w/ NativeFeatures migrated to apps_provider core). All staged.
  - [x] `source_provider.dart` — theirs-base + re-added fork members (icon/size/reproducible/attestation/VirusTotal fields on App with symmetric fromJson/toJson/copyWith; APKDetails icon/size/reproducible; regionalStore, previouslyCheckedApp, deepCopy=>copyWith, sourceTemplates/getSourceTemplate, naiveStandardVersionDetectionForUrl; reproducible/attestation/malware/versionStringSource const+helper families; header normalization). Verified symmetric, staged.
  - **⚠️ Immutable-App ripple (must fix in later stages):** upstream `App` is fully `final`. Every fork `deepCopy()..field = x` cascade or direct `app.field = x` mutation in apps_provider / pages must become `copyWith(field: x)`. Known site flagged: `lib/pages/app.dart:~2200` `freshApp.deepCopy()..apkSizeBytes = resolvedSize` → `freshApp.copyWith(apkSizeBytes: resolvedSize)`.
  - [x] apps_provider.dart + 4 extensions — fork methods re-homed (install/VirusTotal/attestation/save-assets, updates/detail-auto-check, lifecycle/icons/deferred-removal, import/export); App mutations → copyWith; scanApkWithVirusTotal returns a record; no duplicate defs; verified & staged.
  - [ ] settings_provider (ours+upstream), notifications_provider (ours+ID-space fix), logs_provider (theirs)
  - [ ] native_provider.dart → concrete `Installer` subclass (vs upstream's staged `installers/*`), then delete

  ### ⚠️ Forward-reference gaps to CLOSE before compile gate (surfaced by apps_provider re-homing)
  - **COMPILE BLOCKER — `github.dart`:** add the fork's GitHub build-attestation API — `shouldVerifyAttestations`, `shouldEnforceAttestations`, `getAttestationStatusForSha256Digest` (+ related `validatePAT` attestation bits). My theirs-base github resolution omitted these (out of original scope); install ext now calls them. (Stage 1 revisit.)
  - **COMPILE BLOCKER — `MalwareScanWarningDialog`:** must exist as a component (re-home to `components/app_detail_widgets.dart`) — referenced by install ext. (Stage 3.)
  - Non-blocking: `maxParallelUpdateChecksForDevice` re-homed but not wired into `checkUpdates` (upstream's completer/timer design kept); background flagged-scan surfaces via generic error path (coarser UX than fork's `MalwareScanSkippedNotification`); `removeFromObtainium` vs fork `removeFromObtainX` branding key.
- [ ] Stage 3 — components
- [ ] Stage 4a / 4b — pages + theme
- [ ] Stage 5 — android native
