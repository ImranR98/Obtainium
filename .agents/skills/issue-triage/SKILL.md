---
name: issue-triage
description: Triage Obtainium GitHub issues labeled "to check" and re-check open issues labeled "needs follow up" — classify duplicates/invalid/valid, decide autonomous vs human, score importance, close approved duplicates/invalids, then fix autonomous issues with emulator-verified commits. Use when asked to work the "to check" or "needs follow up" queues, triage Obtainium issues, review the issue backlog, or run the issue triage workflow.
compatibility: Requires `gh` authenticated for the repository, the Flutter toolchain (see AGENTS.md), and an Android emulator/device for verification. Read AGENTS.md at the repo root first; its hard rules and commit conventions apply throughout.
---

# Obtainium Issue Triage

Work through the open GitHub issues labeled `to check` (the label is auto-applied to new
issues and means "not reviewed yet") **and re-check the open issues labeled
`needs follow up`**. The flow:

1. Fetch both queues and classify every issue.
2. Score valid issues, and tag each as fixable autonomously or needing a human decision.
3. Present issues one at a time (summary, assessment, comment, labels, close action) for the
   user's review and corrections.
4. Close approved duplicates/invalid/stale issues with a reviewed comment; apply approved
   labels.
5. Fix the approved autonomous issues in importance order, one verified commit each.
6. Report what changed and what remains.

The `needs follow up` queue is a re-check, not a fresh triage: include an issue when the
requester or a community member with relevant information replied after the last maintainer
(or LLM) comment. If there has been no relevant response for **8 weeks**, suggest closing
the issue (usually as `not planned`) instead of leaving it parked indefinitely.

**Before starting, read `AGENTS.md` at the repo root.** The hard rules (no plagiarism, no
version bumps, translation handling, staging, commit style, environment discovery,
verification expectations) live there and are not repeated here. The one extra rule for this
skill: **never close an issue that was fixed** — the maintainer closes those after release.

## Phase 0 — Preflight

- Run from the repo root. If `git status --porcelain` is dirty, ask the user before doing
  anything; do not stash unrelated work.
- Confirm tooling: `gh auth status`; repo slug via
  `gh repo view --json nameWithOwner -q .nameWithOwner` (use it as `$REPO`); Flutter/SDK per
  `AGENTS.md`.
- Create a scratch ledger outside the repo, e.g.
  `/tmp/obtainium-triage/<date>/ledger.md`, and record every decision, approved comment,
  label change, and later commit hash there. Long runs will be compacted; the ledger is the
  memory. Never write triage state into the repo.

## Phase 1 — Fetch the queue

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
for LABEL in "to check" "needs follow up"; do
  gh issue list --repo "$REPO" --label "$LABEL" --state open --limit 100 \
    --json number,title,body,labels,createdAt,updatedAt,comments,reactionGroups
done
```

`scripts/list-to-check.sh` prints a compact one-line-per-issue view; pass the label as the
second argument (`scripts/list-to-check.sh "" "needs follow up"`) to list the follow-up
queue. Always re-fetch: both queues change between runs.

For every `needs follow up` issue, determine whether the requester or another commenter
provided relevant information **after** the last maintainer/LLM comment. If so, include it
in the batch and re-evaluate it from the new evidence. If the last activity is more than
8 weeks old and nobody has supplied the requested information, mark it **suggest close
(stale)** with the date of the last relevant comment; do not keep it in the queue just
because it is old.

Work in batches of roughly 8–10 issues. Read issue bodies selectively and never paste huge
logs wholesale into context (`gh issue view <n> --comments`; long bodies can be filtered
with `gh issue view <n> --json body --jq '.body[0:4000]'`). Some reports (e.g. background-task
logs) are tens of thousands of characters.

## Phase 2 — Classify each issue

Read the body **and all comments** — community members frequently provide the real
diagnosis, and the maintainer often agrees with them. Then pick one category:

- **Duplicate** — find the canonical issue with keyword searches, e.g.
  `gh search issues --repo "$REPO" "<terms>"` and
  `gh issue list --repo "$REPO" --search "<terms>" --state all`. Name the canonical issue.
  - If the canonical issue is closed as fixed, check the reporter's version: if it includes
    the fix, this is a **regression**, not a duplicate — classify it as valid and raise its
    importance.
  - Check whether the earlier fix was reverted later:
    `git log --oneline --grep '#<canonical>'`.
- **Invalid / not applicable** — expected behavior or an available setting (say which),
  unsupported platform/ROM, external cause or blocker, violates the Android app model, or
  already fixed. Cite the concrete constraint or setting in the closing comment.
- **Needs follow up** — not enough information to act. If the issue already carries the
  label, first use any new response to re-classify it. If there is still no usable
  information and the last relevant comment is under 8 weeks old, draft a short, specific
  comment asking for exactly what is missing (exact error text, repro rate, device/OS/build,
  logs); keep it open and keep the `needs follow up` label. If 8 weeks have passed with no
  relevant response, classify it as **suggest close (stale)** and propose a `not planned`
  close.
- **Valid** — a real bug or a reasonable enhancement. Then decide:
  - **Autonomous**: localized code fix; deterministic behavior; testable (unit test and/or an
    e2e suite); no UX/product decision needed; no external account or special hardware;
    verifiable on the emulator that is available; the approach was not recently reverted.
  - **Human**: design/product decisions, installer or security semantics, broad refactors or
    reverts, ROM-specific or non-standard API (root/Shizuku) work, blocked issues, source
    scraping that needs accounts or manual checks, anything ambiguous.

When reading commit references, remember `(#N)` can be a PR, not an issue: check
`gh issue view N` and `gh pr view N`. PR threads are often used as regression trackers
(e.g. #3000).

## Phase 3 — Score importance

Use a P0–P4 scale. Quick version (full calibration and examples in
`references/classification-rubric.md`):

- **P0** — crash, data loss, or security issue; regression from the most recent release;
  breaks update checking/download/install for all users.
- **P1** — core-flow bug (download, install, update check, source parsing) affecting many
  users; major-source breakage; issues already labeled `TODO` or `high priority`.
- **P2** — valid bug with a workaround or narrow scope; widely requested enhancement aligned
  with the maintainer's direction.
- **P3** — niche source, cosmetic, ROM-specific, non-standard API, one-off environment.
- **P4** — not actionable (duplicate, invalid, needs follow up).

Weigh the existing labels, +1 reactions, comment count, recency, and whether the affected
subsystem recently changed. Calibration from history: `high priority` is reserved for
installer/background/update-flow breakage; crashes are typically fixed in days, features can
take weeks–months, and issues blocked on external parties run long.

## Phase 4 — Present and get approval

Present the queue **one issue at a time**, in queue order, unless the user explicitly asks for
a single full-batch table. For each issue show:

1. **Summary** — what the reporter is describing, in one or two sentences.
2. **Assessment** — category, importance, and the evidence behind it: file/line references,
   commit hashes, logs, screenshots, upstream links, community findings. State what you
   verified and what you could not (and why). When a report's own claim looks wrong, say so
   and show the check that proves it.
3. **Proposed comment** — the exact text to post, or "none". Every comment that will actually
   be posted must end with the LLM-review footer (see Phase 5).
4. **Proposed label changes** — remove `to check`; add category labels
   (`UI`, `HTTP`, `installer`, `source-specific`, `non-standard API`, `rom-specific`) and
   priority/parking labels where justified. **Never add the `duplicate` label** — it is
   unused; duplicates are closed with the duplicate reason instead. `info/idea` and `blocked`
   are parking labels; `wontfix` is effectively unused.
5. **Proposed close** — `not planned`, `duplicate of #N`, `needs follow up` (stays open),
   **suggest close (stale)** when 8 weeks have passed without a relevant response, or keep
   open for a code fix/decision.

Then **stop and wait** for *approve / skip / approve-with-edits* before presenting the next
issue. Apply edits, re-present the changed issue if asked, and record each decision in the
ledger. Do not perform any GitHub write or code change until the user approves that issue.

If the user asks for a full-batch table instead, it may use columns:
`| # | Title (linked) | Category | Autonomous? | Importance | Rationale | Workaround / answer | Proposed labels | Draft comment |`.
For valid issues include the proposed workaround/settings answer when that is the right
response instead of a code change (the maintainer does this often).

## Phase 5 — Close and label the rejected issues

Only after approval, per issue:

- Duplicate: `gh issue close <n> --repo "$REPO" --reason duplicate --comment "<reviewed text>"`
  (maintainer style: `Duplicate of #1234 (fixed).` or `Duplicate of #1234. <one-line why>.`).
- Invalid: same command with `--reason "not planned"` and the reviewed one-line rationale.
- Needs follow up: `gh issue comment` the reviewed questions, then
  `gh issue edit <n> --add-label "needs follow up"`; keep it open.
- Stale needs follow up: after approval, close with `--reason "not planned"` and a short
  reviewed comment naming the missing information and the 8-week window.
- Valid: `gh issue edit <n> --remove-label "to check" --add-label ...` with the approved
  labels only.
- Never close fixed issues, and do not post fix/release comments — the maintainer does that
  when releasing.
- **Footer on every posted comment.** All comments (closing comments, follow-up questions,
  any other) must end with a divider, a blank line, and exactly:

  ```text
  ---

  Note: This comment was generated by an LLM, with manual review and approval.
  ```

  When a closing comment is posted via `gh issue close --comment`, include the footer in the
  same body so the comment is never posted without it.

## Phase 6 — Fix the autonomous issues

Process in importance order. Start with 3–5 issues; there is no hard cap, but if the session
grows too large or an issue turns out to need a decision, move it to the human pile and say
so in the report. For each issue:

1. Re-read the issue and comments; reproduce or pin down the failing path in the code.
2. Check history: `git log --oneline --grep '#<n>'` and recent changes in the subsystem. If a
   prior fix for this issue was reverted, flag it rather than re-landing the same approach.
3. Ensure a device: `adb devices` (resolve the SDK per `AGENTS.md`). If nothing is attached,
   ask the user to launch an emulator and list the available AVDs. Do not proceed to device
   verification without one.
4. Implement the minimal fix plus tests (`test/` for logic, `integration_test/` for device
   behavior). Follow `AGENTS.md` conventions.
5. If the change adds user-facing strings: add the key to `assets/translations/en.json`, then
   run `node assets/translations/standardize.mjs` so the other locales get the placeholder in
   the same change. Never edit other locales by hand.
6. Verify: `flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, and the
   relevant on-device check (`./tool/e2e.sh`, a targeted suite, or manual ADB). Capture what
   you ran and saw.
7. Commit exactly this fix: sentence-case subject ending in `(#<n>)`, body covering problem →
   change → verification. One commit per issue. Do not push.
8. Do not comment on or close the issue. Record the commit hash in the ledger.
9. If verification is impossible (e.g. requires unavailable hardware or an account), say so
   plainly — never claim a verification you did not perform.

## Phase 7 — Report

Finish with a concise report:

- Issues closed (number + reason) and labels applied.
- Commits per fixed issue (hash, subject), noting they will ship in the next release.
- Issues moved to human/needs-follow-up, with why.
- Remaining `to check` and `needs follow up` queue sizes, plus any **suggest close (stale)**
   candidates and suggested next steps.

## Gotchas

- Read large issue bodies/logs selectively; they can be enormous.
- The `to check` label is auto-applied by GitHub triage; removing it on valid issues is part
  of the job.
- Subjective style change requests (wording, punctuation, capitalization debates) are often
  pushed back on; do not churn user-facing strings without approval (translations cost).
- Missing-info closures are rare in this repo's history; prefer `needs follow up`, but
  suggest closing once 8 weeks have passed without a relevant response.
- `needs follow up` is not a permanent parking lot: re-check it on every run and act on new
  responses.
- A single logical change can legitimately close several issues; the maintainer bundles when
  appropriate. This skill still commits one fix per issue unless the user says otherwise.
