# 07_INITIAL_2_PR_PLAN.md — Obtainium Initial 2 PR Plan

## Initial PR Selection

| # | Candidate ID | Title | Risk | Size | Rationale |
|---|--------------|-------|------|------|-----------|
| 1 | O-01 | docs: add troubleshooting section for common installation errors | LOW | ~80 | Audit finding, clear value |
| 2 | O-07 | fix: improve error message for 403 Forbidden on source additions | LOW | ~40 | Issue #2921, clear improvement |

**Why not others:**
- O-02, O-06: test-only but need Flutter environment setup to validate
- O-03, O-05, O-09: MED risk, touches core source parsing logic
- O-08: lower priority than O-01

---

## PR #1 (Initial): O-01 — docs: add troubleshooting section for common installation errors

**Branch:** `contrib/obtainium/docs-troubleshooting`
**Linked Issue:** none
**Source:** quality audit
**Target Files:** README.md

### Why This Is An Initial PR
- **Clear value** — helps users avoid common pitfalls
- **No behavior change** — pure documentation
- **Low effort** — straightforward writeup
- **Safe** — HIGH risk repo (security-sensitive APK manager), docs-only is safest

### Implementation Plan
1. Read README.md
2. Find appropriate location (after Installation or Setup section)
3. Write troubleshooting subsection

### Test Plan
- Proof-read for accuracy

### Risk
- **LOW** — docs only

---

## PR #2 (Initial): O-07 — fix: improve error message for 403 Forbidden on source additions

**Branch:** `contrib/obtainium/fix-403-error-message`
**Linked Issue:** #2921
**Target Files:** HTTP client / source error handling

### Why This Is An Initial PR
- **Issue-backed** — #2921 clearly describes the problem
- **Low risk** — only error message change, no behavior change
- **Clear improvement** — users get helpful context instead of opaque 403

### Implementation Plan
1. Find HTTP error handling code
2. Add specific 403 handling with source-specific message
3. Test with a source that returns 403

### Test Plan
- Manual test of adding a source that returns 403
- Verify error message is helpful

### Risk
- **LOW** — error message only, no behavior change

### Fallback Candidate
O-08 (docs: clarify APK variants)

---

## Branch Queue

| Candidate ID | Branch | Title | Tests Run | Risk | Ready For PR | Notes |
|--------------|--------|-------|-----------|------|--------------|-------|
| O-01 | contrib/obtainium/docs-troubleshooting | docs: add troubleshooting | NA (docs) | LOW | NO | Must implement |
| O-07 | contrib/obtainium/fix-403-error-message | fix: improve 403 error message | Manual | LOW | NO | Must implement |

---

## Remaining 3 PRs (not yet opened)

| PR # | Candidate ID | Title | Status |
|------|--------------|-------|--------|
| 3 | O-02 | test: add regression test for Bitwarden authenticator | Planned |
| 4 | O-06 | test: add test for sourcehut source parsing | Planned |
| 5 | O-08 | docs: clarify armv7/arm64 APK variants | Planned |