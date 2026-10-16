#!/usr/bin/env bash
# Read-only listing of the Obtainium issues labeled "to check".
#
# Usage: scripts/list-to-check.sh [owner/repo]
#
# Prints one TSV row per issue, sorted by issue number:
#   number <TAB> created <TAB> labels <TAB> comments <TAB> +1s <TAB> title
#
# Requires `gh` to be authenticated (see AGENTS.md). Makes no changes.
set -euo pipefail

REPO="${1:-${REPO:-}}"
if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO" ]; then
    REPO="ImranR98/Obtainium"
fi

gh issue list --repo "$REPO" --label "to check" --state open --limit 100 \
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
