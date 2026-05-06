#!/usr/bin/env bash
# transfer-issue.sh
#
# Transfers a GitHub issue to a target repo based on a routing label,
# then leaves a stub comment on the original issue.
#
# Required environment variables:
#   GH_TOKEN      — GitHub PAT with repo scope
#   LABEL_PREFIX  — Routing label prefix (e.g. "🐙 ")
#   ISSUE_NUMBER  — Issue number to process
#   ISSUE_TITLE   — Issue title (for logging)
#   ISSUE_LABELS  — JSON array of label objects from the GitHub event

set -euo pipefail

ORG="$GITHUB_REPOSITORY_OWNER"
INBOX_REPO="${GITHUB_REPOSITORY#*/}"

echo "Issue #$ISSUE_NUMBER: $ISSUE_TITLE"

labels=$(echo "$ISSUE_LABELS" | jq -r '.[].name')
echo "Labels: $(echo "$labels" | tr '\n' ' ')"

# Find the first label matching the routing prefix
target_repo=""
while IFS= read -r label; do
  if [[ "$label" == "${LABEL_PREFIX}"* ]]; then
    target_repo="${label#"${LABEL_PREFIX}"}"
    echo "Routing label found: '$label' → repo '$target_repo'"
    break
  fi
done <<< "$labels"

if [ -z "$target_repo" ]; then
  echo "No routing label found. Nothing to do."
  exit 0
fi

# Safety check: don't transfer to the inbox itself
if [ "$target_repo" = "$INBOX_REPO" ]; then
  echo "Target is the inbox repo itself. Skipping."
  exit 0
fi

TARGET="${ORG}/${target_repo}"
echo "Transferring issue #$ISSUE_NUMBER to $TARGET..."

gh issue transfer "$ISSUE_NUMBER" "$TARGET" \
  --repo "${ORG}/${INBOX_REPO}"

echo "Transfer complete."
