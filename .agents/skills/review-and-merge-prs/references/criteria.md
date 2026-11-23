# PR review criteria

Shared judgment guide for the PR-review skill. `scripts/collect.mjs` gathers raw facts
(changed files, diff flags, linked issues, comments, checks, overlaps); every verdict below
is the agent's to make. Repo rules come from `AGENTS.md`, `docs/CONTRIBUTING.md`,
`docs/DEVELOPER_GUIDE.md`, and recent maintainer history.

## How to read collector facts

- `kind` / `scope`: primary PR type and the file groups it touches.
- `mergeable` / `mergeStateStatus`: `CONFLICTING`/`DIRTY` means a human must rebase or
  resolve; `BEHIND` means the PR is behind its base and should be refreshed before merge.
- `checks`: the only PR CI is translation JSON validation. `no-checks` is normal.
- `linked`: closing issue references and mentioned issues, with state. Use them to detect
  duplicates, already-fixed issues, and regressions.
- `overlaps`: files and closing issues shared by more than one open PR. Treat them as a
  merge-order decision, not an automatic failure.
- `flags`: collector heuristics. Confirm anything surprising by reading the diff or body.
- `lastComment` / `lastReview`: use for the stale rule; do not paste whole comment bodies
  into context.

## PR classes and scope

- **Translation-only**: all changed files are under `assets/translations/`.
- **Docs-only**: only `docs/`, `README.md`, `AGENTS.md`, or other prose/metadata.
- **Code**: any `lib/`, `test/`, `integration_test/`, `android/`, or `packages/` change.
- **Mixed**: code plus translations/docs, or several unrelated areas. Normal for features,
  but the scope must still match the title/body.
- **Internal**: the maintainer's own PR (`dev` or an owner-authored branch). List it, but do
  not review or merge it unless the user explicitly asks.

A PR that changes unrelated areas without explanation is not merge-ready. Ask for a split or
a reason.

## Common merge-ready checklist

- Open, not a draft, base `main` (unless it is a requested internal PR), and mergeable.
- Diff matches the title, body, and linked issue; no surprise removals.
- No `version:` change in the root `pubspec.yaml`.
- No `.flutter` submodule pointer change (only the `dependency-updates` workflow may do that).
- No generated artifacts (`build/`, `.dart_tool/`, `data/`, coverage/dist outputs), secrets,
  signing material, or local environment files.
- No unrelated reformatting or mass line-ending changes.
- Commit style is sensible (sentence-case subject, references where applicable). Do not block
  a good change solely on contributor commit wording, and never rewrite their commits.
- All behavior-changing code has verification evidence; docs changes are accurate.
- The change is auditable under the AI policy in `docs/CONTRIBUTING.md` and is tested.

## Translation PRs

The template is `assets/translations/en.json`; every locale must have the same keys in the
same order. `assets/translations/standardize.mjs` enforces this and fills missing keys with
the English value.

Merge-ready only if:

- The changed file is `assets/translations/<locale>.json` (or a justified `en.json` change).
- JSON parses, uses four-space indentation, and ends with a newline.
- Key set and order match `en.json`; no keys are dropped.
- Plural objects have the same subkeys (`one`, `other`, ...) as the template.
- Placeholders match exactly: `{}` counts and named tokens such as `{n}`, `{before}`,
  `{after}`. A translated placeholder (`{antes}` instead of `{before}`) is a bug in the
  changed key.
- Existing translated values are not replaced with English unless that is the stated intent.
  The checker compares each changed key against the merge base and flags regressions.
- `standardize.mjs` produces no diff after the PR is applied.
- `en.json` changes are justified; new keys belong in `en.json` first. Wording changes to
  English strings need maintainer approval because they affect every locale and translation
  tooling.

Do not merge a translation PR that only moves/reformats a complete file into the wrong path
without comparing it to the existing locale. Check for lost translations first.

Do not judge language quality beyond obvious structural problems, placeholder breakage, or
untranslated text in a changed key. Native-speaker review is out of scope.

## Code PRs

### Required local gates

Run from a clean checkout/worktree with the pinned Flutter:

```bash
flutter pub get --enforce-lockfile
flutter analyze
dart format --set-exit-if-changed .
flutter test
```

- `flutter analyze` must be clean.
- `dart format` must report no changes; do not accept a PR that leaves Dart unformatted.
- `flutter test` must pass. Add or update tests in `test/` for logic/widget changes.
- `flutter pub get --enforce-lockfile` when the PR changes `pubspec.yaml` or `pubspec.lock`;
  otherwise `flutter pub get`. A lockfile change after a plain `pub get` is treated as
  pinned-SDK drift, not a PR failure, unless the PR changes dependencies. A pubspec change
  without a matching `pubspec.lock` change is a failure.
- Behavior changes need `./tool/e2e.sh` or a targeted manual/ADB check. If no device is
  attached, stop and ask the user; never claim device verification without one.
- Dependency, plugin, Android, and native changes also need
  `flutter build apk --flavor normal`. F-Droid-specific changes need the `fdroid` flavour
  build when the normal build cannot cover them.

### Code quality and conventions

- K&R bracing; follow the file's existing indentation (two or four spaces; new files four).
- Use `AppLogger` / `Logger` for internal logging, not `print`.
- Use typed `ObtainiumError` subclasses and `rethrowOrWrapError` as described in the
  developer guide; do not add raw `String` errors.
- Do not put side effects in `build()`; use `initState`/post-frame callbacks.
- Prefer `context.select` over `context.watch` for large providers.
- Guard context use after `await` with `if (!context.mounted) return;`.
- Reuse the existing theme, spacing/radius tokens, `AppListTile`, `ConnectedCard`, and form
  widgets instead of hand-rolling UI.
- Keep git dependencies pinned to commit SHAs; do not switch to `ref: main`/`ref: master`.
- Do not change the app version in `pubspec.yaml`.

### User-facing strings

- Every new string uses `tr()` or `plural()` with a key in `assets/translations/en.json`.
- After editing `en.json`, run `node assets/translations/standardize.mjs` so every locale
  receives the key in template order. Never hand-edit another locale's translation.
- New literal `tr('key')`/`plural('key')` calls must reference an existing key. The
  translation checker reports added literals whose keys are missing.
- Removing an `en.json` key requires checking that no code still references it.

### Docs

Update `docs/DEVELOPER_GUIDE.md` and/or `docs/CONTRIBUTING.md` when architecture, conventions,
or developer workflows change. Source additions and new settings should update the relevant
section and the supported-source list in `README.md` where applicable. Docs-only PRs must be
factually accurate against the current code.

## New source PRs

A new source is merge-ready only if:

- It is not already possible with the HTML source (the feature-request template requires
  this).
- The source reliably exposes a version (or pseudo-version) and one or more APK URLs for the
  latest release; previous releases are optional.
- It is generally applicable, not a one-off app-specific scraper, unless the maintainer has
  agreed to the exception.
- It adds one file in `lib/app_sources/`, registers it in `SourceProvider._buildSources()`,
  and follows the `AppSource` conventions (hosts, URL standardization, request headers,
  error types, rate limits).
- It includes tests in `test/`, does not duplicate an existing source, and updates
  `README.md`/docs.
- It was checked against a real page: at least one version and APK URL are extracted
  correctly. Note any Cloudflare/anti-bot limitation honestly.
- It does not add unnecessary dependencies or broad permissions.

Judge API stability and maintenance burden. A source that scrapes a fragile page may still be
acceptable if the failure mode is clean, but call out the risk.

## Android, native, installers, and security

Treat these as high-scrutiny changes:

- `android/app/src/main/AndroidManifest.xml` — permissions, exported components, intent
  filters, deep links, backup rules.
- `lib/installers/`, `lib/providers/apps_provider_install.dart`, root/Shizuku code — command
  construction, quoting, user/profile IDs, package names, path traversal, injection.
- Import/export and JSON migration — untrusted input, file paths, scheme handling, size
  limits, deserialization, identity changes.
- WebView/navigation and external links — allowed schemes/hosts, arbitrary intent launches.
- Credentials and network code — secure storage, TLS, header leakage, logging of secrets.
- Dependencies — pinned git refs, new packages, native code, build scripts.

Check for:

- Shell/SQL/command injection and missing argument quoting.
- Path traversal or arbitrary file writes from imported data.
- URL validation that accepts `javascript:`, `file:`, `content:`, or arbitrary hosts.
- Permission or exported-component expansion without justification.
- Secrets, tokens, keystores, or private keys in the diff.
- Behavior that only works on one Android version/profile without a fallback.

Device verification is required when the change affects install/update behavior. Root or
Shizuku changes may not be verifiable in the available environment; leave them for the user
and state what is unverified.

## Dependency and toolchain PRs

- Root `pubspec.yaml` version must not change.
- Git dependencies remain pinned to commit SHAs.
- `pubspec.lock` must match `pubspec.yaml`.
- Toolchain/Flutter submodule updates belong to the `dependency-updates` skill, not this one;
  flag them and leave them for the user.
- A dependency PR needs `flutter analyze`, `dart format`, `flutter test`, and a release build.
  If behavior can change, device verification is required.

## Verification matrix

| Change | Required checks |
| --- | --- |
| Translation-only | JSON validity, key parity/order, placeholders/plurals, regressions, `standardize.mjs` no-op |
| Docs-only | Diff review, accurate links/claims, whitespace check |
| Dart logic/widgets | `pub get`, `analyze`, `format`, `test` (enforce lockfile if deps change) |
| User-visible behavior | Above plus e2e or targeted device/ADB verification |
| New/changed source | Above plus a real source URL check for version + APK; tests |
| Android/native/installer | Above plus release APK build; device install/update check where possible |
| Dependencies/plugins | Above plus release build and lockfile consistency |
| Toolchain/`.flutter` | Not handled here; route to `dependency-updates` |

## Fix catalog (mechanical only)

Apply only after approval, on the PR branch, with a fix commit:

- Translation JSON: run `standardize.mjs`; fix formatting/final newline; add a missing key to
  `en.json` and standardize (never hand-edit another locale's values).
- `dart format` on changed Dart files.
- Trivial analyzer fixes that do not change behavior (unused imports, `const`, obvious type
  annotations).
- Revert an accidental `pubspec.yaml` version bump.
- Remove generated artifacts or unrelated files that clearly do not belong.
- Add/update docs required by the change.
- Fix a misplaced translation file only after comparing its keys/values with the existing
  locale and confirming no translations are lost; moving a full replacement over community
  work needs explicit user approval.

Not mechanical; send back to the author or decide with the user:

- Behavior, source parsing, installer, security, dependency, or toolchain changes.
- Missing tests for non-trivial logic.
- Translation quality or wording decisions.
- Merge conflicts/rebase decisions.
- Design/product decisions.
- A PR that needs new dependencies or permissions.

## Close catalog

Close only with explicit consent and a reviewed comment:

- **Superseded**: a merged PR/commit already covers the change.
- **Duplicate**: another open PR covers the same issue/scope.
- **Invalid**: version bump only, misplaced file with no new content, wrong target branch,
  already possible with HTML, unsupported source, or a maintainer design/security decision.
- **Stale**: no relevant activity for 8 weeks and the PR is a draft/conflicting, or the author
  has not responded to requested changes. Ask first; if the author returns with a rebase,
  re-review normally.

Do not close merely because a PR is fixable, needs tests, or needs a rebase. Those are author
changes.

## Reporting buckets

- **Ready**: all common and type-specific gates pass; device verification done where needed.
- **Fixable**: only mechanical issues remain.
- **Needs review**: design, UX, security, source policy, translation quality, overlap order,
  or behavior that cannot be verified in the available environment.
- **Needs author changes**: concrete missing tests/docs/changes; keep open.
- **Suggest close**: superseded, duplicate, invalid, or stale.

Include exact evidence (file/line, command output summary, issue/PR links) and state what you
did not verify.

## Known limitations

- The collector does not judge translation quality or semantic correctness.
- There is no general PR CI; local verification is the only gate for code.
- Device behavior cannot be verified without an attached emulator/device.
- Root/Shizuku/ROM-specific behavior may be impossible to verify in the available environment.
- GitHub may hide diffs for very large files; inspect the PR files/API when the digest looks
  incomplete.
