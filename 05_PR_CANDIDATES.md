# 05_PR_CANDIDATES.md — Obtainium PR Candidates

## Candidate List

| ID | Title | Type | Linked Issue | Source | Risk | Size | Merge | Selected |
|----|-------|------|--------------|--------|------|------|-------|----------|
| O-01 | docs: add troubleshooting section for common installation errors | docs | none | audit | LOW | ~80 | HIGH | |
| O-02 | test: add regression test for Bitwarden authenticator duplicate detection | test | #2931 | issue | LOW | ~60 | MED | |
| O-03 | fix: handle 7z release asset parsing for APKs | fix | #2930 | issue | MED | ~80 | MED | |
| O-04 | docs: add note about APKPure source limitations in README | docs | none | audit | LOW | ~40 | HIGH | |
| O-05 | fix: apply APK regex filter to all release asset types | fix | #2929 | issue | MED | ~100 | MED | |
| O-06 | test: add test for sourcehut source parsing | test | #2913 | issue | LOW | ~60 | MED | |
| O-07 | fix: improve error message for 403 Forbidden on source additions | fix | #2921 | issue | LOW | ~40 | HIGH | |
| O-08 | docs: clarify that armv7 and arm64 APKs are separate variants | docs | #2924 | issue | LOW | ~30 | HIGH | |
| O-09 | fix: handle predictive back gesture cancellation in embedded WebView | fix | #2911 | issue | MED | ~80 | MED | |
| O-10 | docs: add FAQ section for common source configuration issues | docs | none | audit | LOW | ~90 | HIGH | |

---

## O-01: docs: add troubleshooting section for common installation errors

- **Linked Issue:** none
- **Source:** quality audit — setup docs could be more helpful
- **Problem:** Users hit common installation errors (Shizuku setup, source configuration) with no troubleshooting help
- **Proposed Solution:** Add troubleshooting section covering Shizuku setup, common source issues, APK signature verification
- **Target Files:** README.md, docs/
- **Test Plan:** Read and verify
- **Risk:** LOW — docs only
- **Expected Diff:** ~80 lines
- **Merge Likelihood:** HIGH
- **Selected:** YES

---

## O-02: test: add regression test for Bitwarden authenticator duplicate detection

- **Linked Issue:** #2931
- **Source:** issue triage
- **Problem:** Bitwarden Authenticator and Bitwarden Password Manager share — duplicate detection may not work correctly
- **Proposed Solution:** Add test for Bitwarden source authenticator detection
- **Target Files:** `lib/providers/bitwarden_authenticator.dart` or test file
- **Test Plan:** Run Flutter tests
- **Risk:** LOW — test only
- **Expected Diff:** ~60 lines
- **Merge Likelihood:** MED
- **Selected:** NO

---

## O-03: fix: handle 7z release asset parsing for APKs

- **Linked Issue:** #2930
- **Source:** issue triage
- **Problem:** APKs packaged in 7z release assets are not detected — source parser only looks for common archive formats
- **Proposed Solution:** Extend source parser to recognize and extract 7z archives for APK detection
- **Target Files:** `lib/models/source.dart`, source implementation
- **Test Plan:** Test with 7z-based release source
- **Risk:** MED — touches source parsing core
- **Expected Diff:** ~80 lines
- **Merge Likelihood:** MED
- **Selected:** NO

---

## O-04: docs: add note about APKPure source limitations in README

- **Linked Issue:** none
- **Source:** audit — APKPure source has known issues
- **Problem:** APKPure source is web-scraping based and frequently fails; docs don't mention limitations
- **Proposed Solution:** Add note in README or source docs about APKPure limitations and alternatives
- **Target Files:** README.md
- **Test Plan:** Read and verify
- **Risk:** LOW
- **Expected Diff:** ~40 lines
- **Merge Likelihood:** HIGH
- **Selected:** NO

---

## O-05: fix: apply APK regex filter to all release asset types

- **Linked Issue:** #2929
- **Source:** issue triage
- **Problem:** "Filter APKs by regular expression" only applies to specific asset types, not all
- **Proposed Solution:** Extend regex filter to apply across all release asset types
- **Target Files:** Source download logic
- **Test Plan:** Test regex filtering with different asset types
- **Risk:** MED — core download logic
- **Expected Diff:** ~100 lines
- **Merge Likelihood:** MED
- **Selected:** NO

---

## O-06: test: add test for sourcehut source parsing

- **Linked Issue:** #2913
- **Source:** issue triage
- **Problem:** Sourcehut source has been failing; no tests to catch regressions
- **Proposed Solution:** Add Flutter test for sourcehut source parsing
- **Target Files:** `lib/providers/sourcehut.dart` or test file
- **Test Plan:** Run flutter test
- **Risk:** LOW — test only
- **Expected Diff:** ~60 lines
- **Merge Likelihood:** MED
- **Selected:** NO

---

## O-07: fix: improve error message for 403 Forbidden on source additions

- **Linked Issue:** #2921
- **Source:** issue triage
- **Problem:** Adding app from rockmods returns 403 error with no useful context
- **Proposed Solution:** Catch 403 specifically and show helpful message about source availability
- **Target Files:** HTTP client / source error handling
- **Test Plan:** Manual test with 403-returning source
- **Risk:** LOW — error message only
- **Expected Diff:** ~40 lines
- **Merge Likelihood:** HIGH
- **Selected:** YES

---

## O-08: docs: clarify that armv7 and arm64 APKs are separate variants

- **Linked Issue:** #2924
- **Source:** issue triage
- **Problem:** Users ask about TV version armv7+64 — confusion about APK architecture variants
- **Proposed Solution:** Add note in README about APK architecture variants (arm64, armv7, universal)
- **Target Files:** README.md
- **Test Plan:** Read and verify
- **Risk:** LOW
- **Expected Diff:** ~30 lines
- **Merge Likelihood:** HIGH
- **Selected:** NO

---

## O-09: fix: handle predictive back gesture cancellation in embedded WebView

- **Linked Issue:** #2911
- **Source:** issue triage
- **Problem:** Cancelling predictive back gesture causes embedded WebView to crash
- **Proposed Solution:** Handle predictive back gesture cancellation properly in WebView wrapper
- **Target Files:** WebView integration code
- **Test Plan:** Test back gesture cancellation
- **Risk:** MED — Android WebView handling
- **Expected Diff:** ~80 lines
- **Merge Likelihood:** MED
- **Selected:** NO

---

## O-10: docs: add FAQ section for common source configuration issues

- **Linked Issue:** none
- **Source:** audit
- **Problem:** Source configuration is complex; users hit issues with regex filters, source-specific settings
- **Proposed Solution:** Add FAQ section covering common source problems
- **Target Files:** README.md, docs/
- **Test Plan:** Read and verify
- **Risk:** LOW
- **Expected Diff:** ~90 lines
- **Merge Likelihood:** HIGH
- **Selected:** NO