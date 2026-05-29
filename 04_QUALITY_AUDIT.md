# 04_QUALITY_AUDIT.md — Obtainium Quality Audit

## HIGH RISK — Security-Sensitive Android App

**Context**: Obtainium downloads and installs APKs from third-party sources. The app's core function is intrinsically security-sensitive: sideloading APKs, credential storage for GitHub PATs, WebView-based app browsing, and installation with elevated privileges (Shizuku).

---

## Documentation Gaps

| Gap | Severity | Details |
|---|---|---|
| **CONTRIBUTING.md missing** | HIGH | No contribution guidelines, PR template, code style, or developer setup guide |
| **No SECURITY.md** | HIGH | No vulnerability disclosure policy, security contact, or known security considerations |
| **No architecture docs** | MEDIUM | No ADRs, component diagrams, or design documents |
| **No API docs** | LOW | No API surface documentation (not an API project but may help contributors) |
| **No build.md** | MEDIUM | No written build instructions (only `build.sh` script) |
| **License is "LICENSE.txt" but not identified** | LOW | No license header in source files |

### CONTRIBUTING.md Absence
- No development setup guide
- No commit message conventions
- No PR template or checklist
- No test expectations
- First-time contributors have no guidance

### SECURITY.md Absence
- No responsible disclosure policy
- No vulnerability reporting process
- No记录的 security considerations
- Certificate pinning (Issue #2916) has been open since May 2025 with no visible security response

---

## Validation Gaps

### Test Coverage
| Area | Status | Notes |
|---|---|---|
| **Unit tests** | ❌ NONE | `test/widget_test.dart` is a placeholder counter test |
| **Integration tests** | ❌ NONE | No Flutter integration test infrastructure |
| **Widget tests** | ❌ NONE | Only placeholder smoke test |
| **Golden tests** | ❌ NONE | No UI regression tests |
| **E2E tests** | ❌ NONE | No driver-based E2E testing |

### Code Quality Tools
| Tool | Status | Notes |
|---|---|---|
| **flutter analyze** | ⚠️ NOT RUN | Flutter not installed in environment |
| **Dart analyzer** | ⚠️ NOT RUN | Same |
| **Dependency audit** | ❌ NONE | No `flutter pub outdated` or `dart pub outdated` checks in CI |
| **Security advisories** | ❌ NONE | No automated CVE scanning |
| **Dependency pinning** | ⚠️ LOOSE | `pubspec.yaml` uses caret ranges (`^1.6.0`) — auto-upgrades could break things |

### Lint Configuration
- `analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` — minimal enforcement
- No custom lint rules for security, best practices, or Obtainium-specific concerns
- No `avoid_print`, `prefer_single_quotes`, or other helpful rules enabled

---

## Security Audit Findings

### 1. No Certificate Pinning
- **Issue**: #2916 (OPEN since May 2025)
- **Risk**: MITM attack on HTTP requests from any source
- **Note**: `allowInsecure` flag explicitly allows HTTP (useful for corporate ITF/CAs, but adds risk)
- **Status**: Unresolved, acknowledged as enhancement

### 2. WebView-Based Browsing
- **Component**: `webview_flutter ^4.13.1`
- **Risk**: WebView is a known attack surface (CVE history for Android WebView)
- **Controls**: None visible in scanned source (no WebView settings hardening)
- **Note**: Used for app detail/in-app browser view

### 3. GitHub PAT Storage
- **Location**: Settings → GitHub source configuration
- **Risk**: PAT stored locally (sqflite/shared_preferences), potential exposure if device compromised
- **Transport**: Sent with GitHub API requests — should use HTTPS
- **Note**: PAT can be stored in source-specific settings

### 4. Third-Party Source Scraping (Inherent Risk)
- Sources like APKPure, Aptoide, Uptodown are scraped
- No source authenticity verification
- APK signatures from third-party sources not verified against expected hashes
- **Issue #651**: Verify Google Play APKs signed by Google (OPEN)
- HTML-based sources are fragile and can break (#2816)

### 5. APK Signature Verification
- App installs check certificate hash post-install (SHA-256)
- `AppInMemory.certificateHashes` uses `sha256.convert(signature)` on APK signing certificates
- This is good verification, but only *after* installation
- No pre-install verification against known-good hashes

### 6. Shizuku/Installer Integration
- `shizuku_apk_installer` and `android_package_installer` (custom forks) run with elevated privileges
- These are git dependencies from ImranR98/AlexBacich/re7gog — third-party packages
- No pinned versions — using `ref: main` or `ref: master`
- **TODO in pubspec.yaml**: `android_package_manager` marked "Make PR and switch to upstream"

### 7. shared_storage (Maintenance Concern)
- **pubspec.yaml TODO**: "Is this maintained?"
- Git dependency on `AlexBacich/shared-storage` — no version pin
- Potentially unmaintained package handling broad storage permissions

### 8. APK Downloads via HTTP
- `downloadFile()` in `apps_provider.dart` makes HTTP range requests
- `allowInsecure` flag permits HTTP URLs explicitly
- Used for `sourceRequestStreamResponse` — no visible certificate validation bypass code, but the flag exists

### 9. In-Memory Secrets in Logs
- `logs_provider.dart` tracks logs
- No evidence of log redaction — GitHub PATs or other credentials could be logged (if passed as URL params)
- **Recommendation**: Add credential redaction to log output

---

## Edge Cases & Error Handling Audit

### Version Parsing
- `generateStandardVersionRegExStrings()` produces 100s of patterns — potential DoS via catastrophic backtracking on malicious input
- Scanned: `RegExp('^$pattern\$')` with `strict=true` uses anchors — safe
- Scanned: `strict=false` uses `strict=false` substring matching — safe from catastrophic backtracking

### Download Resumption
- `downloadFile()` handles partial downloads via Range headers
- Polling loop every 7 seconds waiting for existing download to progress
- No cancelation mechanism visible (long downloads could stall)

### Archive Extraction
- `flutter_archive` handles ZIP/XAPK extraction
- Potential zip bomb /深情文解压轰炸 attack
- No size limits on extracted content observed
- Issue #2868 (APK not found in ZIP with subfolder) suggests extraction path handling is incomplete

### Multi-Platform
- minSdk=26 (Android 8.0) — excludes Android 7 (Issue #2851)
- Flutter flavor dimension separates Google Play and F-Droid builds
- TV-specific UI bugs (#2879, #2884) suggest TV platform not fully tested

### Thread/Async Safety
- `apps_provider.dart` uses `AsyncTask` but async patterns not fully scanned
- No evidence of mutex/critical section protection for shared state
- `Provider` for state management but no explicit thread safety

### HTML Parsing
- `html ^0.15.6` used for page parsing
- XSS risk if scraped HTML rendered in WebView without sanitization
- `ensureAbsoluteUrl()` in `html.dart` resolves relative URLs — potential URL injection

### Error Class Hierarchy
- `custom_errors.dart` has well-structured error classes
- `MultiAppMultiError` aggregates multi-app errors with helpful grouping
- Error messages localized — good i18n practice

---

## Data Handling

### Local Storage
| Data | Storage | Sensitivity |
|---|---|---|
| App list + settings | sqflite DB | Medium — includes source URLs, credentials |
| GitHub PAT | shared_preferences (?) | High — write access to GitHub repos |
| App icons | Filesystem (`path_provider`) | Low |
| Downloaded APKs | Filesystem | High — arbitrary code execution |
| Export/Import JSON | User-selected directory | Medium |

### Export/Import
- `import_export.dart` supports JSON backup/restore
- Includes `additionalSettings` (`additionalData` migrated)
- Credentials included in export if not encrypted — **potential credential leak in plaintext backups**

### No Encryption Observed
- No `encrypt` or `crypto` usage for local storage in scanned files
- PAT storage is plaintext (shared_preferences)
- Backup files are ZIP archives with no encryption

---

## CI/CD Audit

### release.yml
| Check | Finding |
|---|---|
| Trigger | Manual only — no automated triggers |
| Secrets | `GH_ACCESS_TOKEN` used — needs repo-level token with tag/release perms |
| Artifacts | APKs saved as unsigned artifacts — ❌ NOT SIGNED in CI |
| Code signing | Removed signing config for CI: `sed -i 's/signingConfig = signingConfigs.getByName("release")//g'` |
| Reproducible builds | F-Droid claims reproducible but `dev` flavor normal build is unsigned |
| Inputs | `beta` boolean for pre-release flag — good |

### fastlane.yml
- F-Droid deployment — metadata in `fastlane/metadata/`
- Standard fastlane workflow

### translation-validate.yaml
- Only checks JSON syntax with `jq empty`
- No content validation (translations could be empty or wrong keys)
- Only validates changed files — reduces noise

---

## Known Maintenance Liabilities

| Item | Severity | Details |
|---|---|---|
| `android_package_installer` PAT | MEDIUM | TODO: "See if PR will be accepted (dev may not be active)" |
| `android_package_manager` upstream | MEDIUM | TODO: "Make PR and switch to upstream" |
| `shared_storage` maintenance | MEDIUM | TODO: "Is this maintained?" |
| `.flutter` as submodule | MEDIUM | Flutter managed as git submodule |
| 31 source scrapers | HIGH | Each source is a maintenance burden; site changes break them |
| No test coverage | HIGH | Changes could break without detection |

---

## Summary of Findings

| Category | Rating | Notes |
|---|---|---|
| Documentation | ⚠️ POOR | No CONTRIBUTING.md, no SECURITY.md, no arch docs |
| Test Coverage | ❌ CRITICAL | No real tests — placeholder only |
| Security | ⚠️ RISKY | No cert pinning, WebView, git deps, HTTP allowed |
| Dependency Pins | ⚠️ LOOSE | Caret ranges + git refs — could auto-upgrade unexpectedly |
| CI/CD | ⚠️ ACCEPTABLE | Unsigned APKs in artifacts, manual-only release |
| Error Handling | ✅ GOOD | Structured error class hierarchy |
| i18n | ✅ GOOD | eary_localization with crowdsourced translations |
| Source Maintenance | ⚠️ HIGH BURDEN | 31 scrapers + 3 git deps + frequent breakage |

---

## Top Recommendations

1. **[CRITICAL] Add test coverage** — At minimum:
   - Unit tests for version parsing (regEx generation)
   - Unit tests for error class behavior
   - Widget tests for critical flows (add app, install)
   - E2E tests for top-3 source types (GitHub, GitLab, F-Droid)

2. **[HIGH] Create CONTRIBUTING.md** — Minimal:
   - Dev environment setup
   - Code style (Flutter defaults OK)
   - PR checklist (tests, analyze, no secrets)

3. **[HIGH] Create SECURITY.md** — At minimum:
   - Vulnerability reporting process
   - Acknowledge Issue #2916 (cert pinning) with timeline or explicit won't-fix

4. **[MEDIUM] Pin dependencies** — Change all `^X.Y.Z` to exact `X.Y.Z` or lock file and commit `pubspec.lock`

5. **[MEDIUM] Audit git dependencies** — Either commit to maintaining forks or switch to upstream alternatives:
   - `android_package_installer`
   - `android_package_manager`
   - `shared_storage`

6. **[MEDIUM] Redact credentials from logs** — Before logging URLs/query params that may contain PATs

7. **[LOW] Sign APKs in CI** — Current unsigned artifacts mean anyone could inject code
