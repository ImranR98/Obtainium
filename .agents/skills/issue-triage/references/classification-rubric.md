# Classification Rubric

Reference data for the triage skill. Everything here was derived from the repository's own
history and issue discussions; it is guidance, not a substitute for reading the issue.

## Base rates and context

- The repo carries a large backlog: hundreds of open issues, with roughly 1–2 new issues a day
  labeled `to check`.
- Historically, completed closes outnumber not-planned closes roughly 947 to 688. Expect a
  meaningful minority of the queue to be rejectable, not fixable.
- The `duplicate` label exists but is unused. Duplicates are closed with the `duplicate`
  reason and a comment. `wontfix` is essentially unused. `info/idea` and `blocked` are the
  parking labels.
- GitHub's automatic triage applies `to check` to new issues; the bug/feature templates
  already require device, OS, version, and repro, so basic details are usually present.

## Duplicate

Search titles/bodies/comments by the distinctive terms in the report (app name, URL, error
text). Name the canonical issue in the comment.

Examples of the maintainer's style:

- `Duplicate of #3070 (fixed)` — original already fixed.
- `Duplicate of #3045. There is a setting in the latest version you can use to turn off this UI.`
- Duplicates are sometimes acknowledged in-thread instead of closed, and off-topic comments
  are split into new issues (`Originally posted by @user in #N`).

**Regression check (do not skip).** If the canonical issue is closed as fixed, look at the
reporter's version. If it includes the fix, the symptom has returned — classify as a valid
regression, importance P1 or higher, and say so. History: #3018 was fixed, reopened, fixed
again, and closed ~2 months later; #830 reopened; #3078 and #3249 were fixed and then
reverted. Also check `git log --oneline --grep '#<canonical>'` for reverts before proposing
the same fix again.

## Invalid / not applicable

Close with the duplicate-style brevity, but explain the concrete reason. Observed patterns:

- **Platform constraint**: #2078 (update-ownership API only applies to fresh installs),
  #2441 (a release can legitimately contain multiple different APKs per version), #2338
  (logs are untranslated because they are for developers).
- **Android app model**: #3289 (two apps cannot share one package name; Obtainium will not
  re-sign/repackage apps). Community members often supply this analysis and the maintainer
  agrees — cite it if so.
- **External cause**: #2335 (upstream APKMirror Cloudflare/403 behavior), third-party site
  changes, server-side rate limits.
- **User error / expected behavior with a setting**: #3325, #3064 (setting exists), #3342
  ("Verify the 'latest' tag", pre-release toggles), #3092 (use "latest asset upload as
  release date").
- **Unsupported environment**: strong-ROM divergences (e.g. HarmonyOS), devices/services
  unavailable to AOSP APIs.

When an issue is valid but the answer is a setting or workflow rather than code, keep it
valid and include the workaround in the presentation — the maintainer regularly does this
instead of changing code (#860 changelog via tapping the version, #1309 required permission
for imports, #3070 background-check semantics).

## Needs follow up

Prefer this over closing when the report lacks what is needed to act. The maintainer's
diagnostic questions are specific; imitate them:

- exact error text (not just "it fails") — #634
- reproducibility rate, steps, screen recording or logs — #608, #634
- Android version and device — #2078, #830 (locale codes), #608
- which settings are enabled and which version last worked (regression framing) — #3070

Post the reviewed questions and add `needs follow up`; keep the issue open.

Re-check the `needs follow up` queue on every run. If the requester or another commenter
supplied relevant information after the last maintainer/LLM comment, re-classify the issue
from that evidence. If no relevant response has arrived for 8 weeks, suggest closing it as
stale (`not planned`) rather than leaving it parked indefinitely.

## Valid

Then decide autonomous vs human:

**Usually autonomous**: localized parser/version/source fixes (#3298, #3303), settings toggles
(#2962, #3251), layout/affordance nits with a clear expected result (#3147), defensive guards
(#3078 follow-ups), unit-testable logic.

**Usually human**: UI overhaul/design direction (#3000 and its regression fallout), installer
semantics and security behavior (#3091 signature/install handling), anything that effectively
reverts another deliberate change (#3249, #3078), broad refactors, ROM-specific or
`non-standard API` (root/Shizuku) work, external blockers, subjective wording/style debates.
Long tails belong to external dependencies: #1973 took ~4.5 months with an upstream vendor
involved, and #682 (XAPK) is still open after years with `help wanted`/`high priority`.

## Importance calibration (P0–P4 in the skill)

Observed priorities:

- `high priority` is reserved for installer/background/update-task breakage (#608, #682).
- `TODO` means "focus for the next release"; `low priority` means "the dev may not work on
  it, PRs are welcome"; `non-standard API` explicitly means the owner is unlikely to work on
  it; `blocked` means dependent on external changes.
- Fix latency: crashes are often fixed same-day (#3018), core/regression bugs within days
  (#3303 one day, #3043 five days), features typically 2–6 weeks to a couple of months
  (#1943, #2441, #2979, #2078). Use this to sanity-check an importance score, not to inflate
  it: an unresolved old issue is not automatically important — some are deliberately parked.
- Cheap, objective copy/grammar fixes are accepted when clearly correct (#2121 "Wi-Fi"),
  often with `good first issue`; subjective style changes are pushed back on or resolved
  per-language (#2245 Oxford comma, #2338 sentence case). Treat string churn as needing
  approval because it affects translations.

Signals that raise importance: reporter says it worked in a previous version (regression),
mentions crash/data loss/signature mismatch, many +1 reactions or "same here" comments,
the issue is already labeled `TODO`/`high priority`, or it affects GitHub/F-Droid/downloads/
installation for all users. Signals that lower it: ROM-specific, `non-standard API`, one
obscure source, purely cosmetic, or requiring behavior Android does not support.

## Community diagnosis

Read every comment before classifying. Technical users frequently post the root cause or a
working workaround (e.g. APKMirror's admin in #1973, reverse-engineering in #682, the Android
app-model explanation in #3289, regex/pre-release guidance in #3342). Incorporate their
findings, credit them in the rationale when relevant, and do not overrule a well-argued
explanation without evidence. The maintainer's replies are often just agreement plus a fix or
a label.
