#!/usr/bin/env bash
# sync-linear-labels.sh
#
# For every non-archived repo in the GitHub org (excluding the inbox repo),
# ensures a corresponding label exists in Linear under the configured group.
# Labels in the group that no longer correspond to a repo are deleted.
# If the inbox repo is private, only private repos are considered as targets
# (GitHub cannot transfer issues from a private repo to a public one).
#
# Required environment variables:
#   GH_TOKEN         — GitHub PAT with read:org scope
#   LINEAR_API_KEY   — Linear personal API key
#   LINEAR_TEAM_ID   — UUID of the Linear team to create labels in
#   LABEL_PREFIX     — Prefix for label names (e.g. "🐙 ")
#   LINEAR_GROUP     — Name of the Linear label group (e.g. "repo")

set -euo pipefail

ORG="$GITHUB_REPOSITORY_OWNER"
INBOX_REPO="${GITHUB_REPOSITORY#*/}"

linear_post() {
  # Takes a jq expression that produces a {"query":..,"variables":..} object.
  # Using jq to build the payload means queries can be pretty multiline strings
  # and variables are safely encoded without manual escaping.
  local response
  if ! response=$(jq -n "$1" \
    | curl -s --show-error -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d @-); then
    echo "Linear API request failed (HTTP error)" >&2
    exit 1
  fi

  # Abort if the response contains a GraphQL errors field
  if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
    echo "Linear API error:" >&2
    echo "$response" | jq '.errors' >&2
    exit 1
  fi

  echo "$response"
}

# Detect inbox repo visibility and limit target repos accordingly.
# GitHub cannot transfer issues from a private repo to a public one.
echo "Detecting inbox repo visibility..."
is_private=$(gh repo view "$ORG/$INBOX_REPO" --json isPrivate --jq '.isPrivate')

if [ "$is_private" = "true" ]; then
  echo "Inbox is private — limiting targets to private repos only."
  visibility_flag="--visibility private"
else
  echo "Inbox is public — including all repos as targets."
  visibility_flag=""
fi

echo "Fetching repos for org: $ORG"
# shellcheck disable=SC2086
repos=$(gh repo list "$ORG" \
  --no-archived \
  $visibility_flag \
  --json name \
  --limit 500 \
  --jq "[.[] | select(.name != \"$INBOX_REPO\") | .name]")

echo "Repos found: $(echo "$repos" | jq length)"

# Fetch the label group and its children in one request.
# Filter by name only — Linear does not support isGroup as a filter field.
echo "Fetching label group '$LINEAR_GROUP' and existing labels..."
group_response=$(linear_post '
  {
    "query": "
      query($teamId: ID!, $groupName: String!) {
        issueLabels(filter: {
          team: { id: { eq: $teamId } }
          name: { eq: $groupName }
        }) {
          nodes {
            id
            name
            children {
              nodes {
                id
                name
              }
            }
          }
        }
      }
    ",
    "variables": {
      "teamId": $ENV.LINEAR_TEAM_ID,
      "groupName": $ENV.LINEAR_GROUP
    }
  }
')

group_id=$(echo "$group_response" | jq -r '.data.issueLabels.nodes[0].id // ""')

if [ -z "$group_id" ]; then
  echo "Label group '$LINEAR_GROUP' not found, creating..."
  create_response=$(linear_post '
    {
      "query": "
        mutation($name: String!, $teamId: String!) {
          issueLabelCreate(input: {
            name: $name
            isGroup: true
            teamId: $teamId
            color: \"#6e6e6e\"
          }) {
            success
            issueLabel {
              id
              name
            }
          }
        }
      ",
      "variables": {
        "name": $ENV.LINEAR_GROUP,
        "teamId": $ENV.LINEAR_TEAM_ID
      }
    }
  ')
  group_id=$(echo "$create_response" | jq -r '.data.issueLabelCreate.issueLabel.id')
  # JSON array of {id, name} objects for existing labels in the group
  existing_labels='[]'
  echo "Created label group with id: $group_id"
else
  existing_labels=$(echo "$group_response" | jq '.data.issueLabels.nodes[0].children.nodes')
  echo "Found label group id: $group_id"
fi

echo "Existing label count: $(echo "$existing_labels" | jq length)"

export LINEAR_GROUP_ID="$group_id"

# Delete labels in the group that no longer correspond to a repo
deleted=0

while IFS= read -r label_id; do
  label_name=$(echo "$existing_labels" | jq -r --arg id "$label_id" '.[] | select(.id == $id) | .name')
  repo_name="${label_name#"${LABEL_PREFIX}"}"

  still_exists=$(echo "$repos" | jq -r --arg r "$repo_name" 'any(. == $r)')

  if [ "$still_exists" = "true" ]; then
    continue
  fi

  echo "  [delete] $label_name (repo '$repo_name' not found)"
  LINEAR_LABEL_ID="$label_id" linear_post '
    {
      "query": "
        mutation($id: String!) {
          issueLabelDelete(id: $id) {
            success
          }
        }
      ",
      "variables": {
        "id": $ENV.LINEAR_LABEL_ID
      }
    }
  ' > /dev/null

  deleted=$((deleted + 1))

done < <(echo "$existing_labels" | jq -r '.[].id')

# For each repo, ensure a corresponding Linear label exists
created=0
skipped=0

while IFS= read -r repo; do
  label_name="${LABEL_PREFIX}${repo}"

  already_exists=$(echo "$existing_labels" | jq -r --arg n "$label_name" 'any(.[]; .name == $n)')

  if [ "$already_exists" = "true" ]; then
    echo "  [skip] $label_name"
    skipped=$((skipped + 1))
    continue
  fi

  echo "  [create] $label_name"
  LINEAR_LABEL_NAME="$label_name" linear_post '
    {
      "query": "
        mutation($name: String!, $teamId: String!, $parentId: String!) {
          issueLabelCreate(input: {
            name: $name
            teamId: $teamId
            parentId: $parentId
            color: \"#6e6e6e\"
          }) {
            success
            issueLabel {
              id
              name
            }
          }
        }
      ",
      "variables": {
        "name": $ENV.LINEAR_LABEL_NAME,
        "teamId": $ENV.LINEAR_TEAM_ID,
        "parentId": $ENV.LINEAR_GROUP_ID
      }
    }
  ' > /dev/null

  created=$((created + 1))

done < <(echo "$repos" | jq -r '.[]')

echo ""
echo "Done. Created: $created, Skipped: $skipped, Deleted: $deleted"