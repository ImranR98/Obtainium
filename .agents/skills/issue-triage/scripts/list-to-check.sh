#!/usr/bin/env bash
# Read-only listing of open Obtainium issues labeled "to check" or "needs follow up".
#
# Usage: scripts/list-to-check.sh [owner/repo] [label]
#
# The label defaults to "to check"; pass "needs follow up" to list the follow-up queue.
#
# Prints one TSV row per issue, sorted by issue number:
#   number <TAB> created <TAB> labels <TAB> comments <TAB> +1s <TAB> title
#
# Requires `gh` to be authenticated (see AGENTS.md). Makes no changes.
set -euo pipefail

REPO="${1:-${REPO:-}}"
LABEL="${2:-to check}"
if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO" ]; then
    REPO="ImranR98/Obtainium"
fi

gh issue list --repo "$REPO" --label "$LABEL" --state open --limit 100 \
    --json number,title,createdAt,labels,comments,reactionGroups \
    --jq '.[] | [
        (.number | tostring),
        (.createdAt[0:10]),
        ([.labels[].name] | join(",")),
        (.comments | length | tostring),
        ((([.reactionGroups[]?.users.totalCount] | add) // 0) | tostring),
        .title
    ] | @tsv' |
    sort -n
