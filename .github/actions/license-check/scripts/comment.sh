#!/usr/bin/env bash
# Create or update the single license-check comment on a pull request.
#
# Env: GH_TOKEN, REPO (owner/name), PR_NUMBER, REPORT_FILE, optional REPORT_JSON.
# Posts nothing when the PR changed no dependencies and no earlier comment exists,
# so PRs that don't touch lockfiles stay quiet.
set -euo pipefail

: "${GH_TOKEN:?}" "${REPO:?}" "${PR_NUMBER:?}" "${REPORT_FILE:?}"
marker='<!-- license-check-report -->'

ids=$(gh api --paginate "repos/$REPO/issues/$PR_NUMBER/comments" \
  --jq ".[] | select(.body | startswith(\"$marker\")) | .id") || ids=""
existing="${ids%%$'\n'*}"

checked=""
if [ -n "${REPORT_JSON:-}" ] && [ -f "$REPORT_JSON" ]; then
  checked=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["results"]))' "$REPORT_JSON")
fi

if [ -z "$existing" ] && [ "$checked" = "0" ]; then
  echo "No dependency changes and no earlier comment; nothing to post."
  exit 0
fi

body_file=$(mktemp)
python3 -c 'import json,sys; print(json.dumps({"body": open(sys.argv[1]).read()}))' "$REPORT_FILE" > "$body_file"

if [ -n "$existing" ]; then
  gh api --method PATCH "repos/$REPO/issues/comments/$existing" --input "$body_file" > /dev/null
  echo "Updated comment $existing"
else
  gh api --method POST "repos/$REPO/issues/$PR_NUMBER/comments" --input "$body_file" > /dev/null
  echo "Posted new comment"
fi
