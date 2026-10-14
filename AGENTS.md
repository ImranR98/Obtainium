# Agent Guide for Obtainium

Obtainium is a Flutter (Android-first) app that installs and updates Android apps directly
from their release sources. This file contains rules and conventions that apply to **all**
agents working in this repository, regardless of the task.

Read these first when relevant:

- [docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md) — architecture, subsystems, and where to start for common tasks.
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) — code style, logging, translations, AI policy.

## Hard rules

1. **Don't plagiarize.** Do not copy large amounts of code, or entire approaches, from other
   pieces of software — especially forks of Obtainium. Small snippets from web search results
   are fine, and you may take freely from official documentation or from the source of
   Obtainium's own dependencies (e.g. Flutter or plugin docs and sources). These are
   guidelines, not strict rules: use common sense about when copying crosses the line into
   plagiarism. If a task seems to require borrowing substantial code or a whole approach from
   another project, stop and flag it loudly to the user first.
2. **Never change the version in `pubspec.yaml`** — version bumps are release-time maintainer
   commits.
3. **Translations**: only add/modify keys in `assets/translations/en.json`. After editing it,
   run `node assets/translations/standardize.mjs` so every other locale file receives the new
   keys in the template order (filled with the English placeholder). Never hand-edit other
   locales — they are community/Weblate-owned. The script warns before dropping keys that are
   missing from the template; `git` is the backup.
4. **Stage explicitly.** Use `git add <path> ...`; never `git add -A` or `git add .`. Never
   stage or modify the `.flutter` submodule, `build/`, `data/`, or generated artifacts.
5. **Do not add code comments** unless asked. Keep the K&R bracing style and the indentation
   of the file being edited (new files use 4 spaces).
6. All user-facing strings go through `tr()` / `plural()` with a key in `en.json`.
7. Use `AppLogger` for internal logging (see `docs/CONTRIBUTING.md`).
8. Per the AI policy in `docs/CONTRIBUTING.md`: only produce code you can audit, and test it.

## Environment

- Flutter: use the pinned submodule at `./.flutter/bin/flutter` when present, otherwise
  `flutter` from `PATH`.
- Android SDK: resolve `$ANDROID_HOME`, then `$ANDROID_SDK_ROOT`, then `~/Android/Sdk`.
  ADB is at `<sdk>/platform-tools/adb`, the emulator binary at `<sdk>/emulator/emulator`.
- `gh` is authenticated for this repository's GitHub remote; prefer it for issue/PR reads and
  writes (GitHub MCP tools are an acceptable alternative). Get the repo slug from
  `gh repo view --json nameWithOwner -q .nameWithOwner`.
- If a change needs device verification and `adb devices` shows nothing, **ask the user to
  launch an emulator or connect a device** — do not launch one yourself. List candidates with
  `<sdk>/emulator/emulator -list-avds`.

## Build, test, verify

```bash
flutter pub get
flutter analyze                            # must be clean
dart format --set-exit-if-changed .
flutter test                               # unit/widget tests under test/
./tool/e2e.sh [--phone|--tv] [--no-install] # emulator suites; discovers them itself
```

- Behavior changes must be verified on a live emulator/device (`tool/e2e.sh`, `flutter run`,
  and/or ADB checks and screenshots). State plainly in the commit body what was verified and
  how. Never claim verification you did not do.
- `tool/e2e.sh` is the source of truth for the E2E suites and their prerequisites; run
  `./tool/e2e.sh --help`. Suites live in `integration_test/`.
- Add or update tests for logic/UI changes: unit/widget tests in `test/`, device suites in
  `integration_test/`.

## Commits and PRs

- Match the current commit style: a sentence-case subject ending with the relevant issue
  reference(s) in parentheses, for example:

  ```text
  Fix icon cache invalidation on app updates (#3306)
  ```

  Multiple references are fine, e.g. `... (#271, #393) (#502)`.
- Non-trivial changes need a body covering: what the problem was, what the change does, and
  how it was verified. Recent commits are the best reference for tone and length.
- One logical change per commit. Do not add generated-by/co-author/tool footers.
- Do not push, open PRs, or comment on issues unless the user asks.

## Docs

When a change affects architecture, conventions, or developer workflows, update
`docs/DEVELOPER_GUIDE.md` and/or `docs/CONTRIBUTING.md` in the same change (required by
CONTRIBUTING).
