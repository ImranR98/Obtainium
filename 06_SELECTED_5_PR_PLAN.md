# 06_SELECTED_5_PR_PLAN.md — Obtainium Selected 5-PR Plan

## Selected PRs

| # | Candidate ID | Title | Type | Risk | Size | Rationale |
|---|--------------|-------|------|------|------|-----------|
| 1 | O-01 | docs: add troubleshooting section for common installation errors | docs | LOW | ~80 | Audit finding, helps users |
| 2 | O-07 | fix: improve error message for 403 Forbidden on source additions | fix | LOW | ~40 | Issue #2921, clear improvement |
| 3 | O-02 | test: add regression test for Bitwarden authenticator duplicate detection | test | LOW | ~60 | Issue #2931, regression test |
| 4 | O-06 | test: add test for sourcehut source parsing | test | LOW | ~60 | Issue #2913, regression test |
| 5 | O-08 | docs: clarify that armv7 and arm64 APKs are separate variants | docs | LOW | ~30 | Issue #2924, clears user confusion |

---

## PR #1: O-01 — docs: add troubleshooting section for common installation errors

**Linked Issue:** none
**Source:** quality audit
**Target Files:** README.md

### Problem
Users hit common installation errors (Shizuku setup, source configuration) with no troubleshooting help.

### Solution
Add troubleshooting section covering:
- Shizuku setup steps and common failures
- Source configuration tips
- APK signature verification
- Debug log access

---

## PR #2: O-07 — fix: improve error message for 403 Forbidden on source additions

**Linked Issue:** #2921
**Source:** issue triage
**Target Files:** HTTP client / source error handling

### Problem
Adding app from rockmods returns 403 with no useful context.

### Solution
Catch 403 specifically and show helpful message about source availability and alternative sources.

---

## PR #3: O-02 — test: add regression test for Bitwarden authenticator duplicate detection

**Linked Issue:** #2931
**Source:** issue triage
**Target Files:** Bitwarden source test file

### Problem
Bitwarden Authenticator and Password Manager share causes duplicate detection issues.

### Solution
Add test that verifies Bitwarden source handling handles authenticator duplicates correctly.

---

## PR #4: O-06 — test: add test for sourcehut source parsing

**Linked Issue:** #2913
**Source:** issue triage
**Target Files:** Sourcehut provider test file

### Problem
Sourcehut source has been failing; no regression tests.

### Solution
Add Flutter test for sourcehut source parsing.

---

## PR #5: O-08 — docs: clarify that armv7 and arm64 APKs are separate variants

**Linked Issue:** #2924
**Source:** issue triage
**Target Files:** README.md

### Problem
Users confused about APK architecture variants.

### Solution
Add note in README explaining APK architecture variants (arm64, armv7, universal).