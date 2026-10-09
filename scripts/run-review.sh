#!/usr/bin/env bash
set -Eeuo pipefail

readonly GITHUB_MCP_IMAGE="ghcr.io/github/github-mcp-server:v0.32.0"

write_conclusion() {
  printf 'conclusion=%s\n' "$1" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

skip() {
  printf 'Kiro cost review skipped: %s\n' "$1"
  write_conclusion "skipped"
  exit 0
}

if [[ -z "${INPUT_KIRO_API_KEY:-}" ]]; then
  echo "kiro_api_key is required" >&2
  exit 1
fi
if [[ -z "${INPUT_GITHUB_TOKEN:-}" ]]; then
  echo "github_token is required" >&2
  exit 1
fi
if [[ ! "${INPUT_MAX_DIFF_SIZE:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo "max_diff_size must be a positive integer" >&2
  exit 1
fi
if [[ "${INPUT_DEBUG:-false}" != "true" && "${INPUT_DEBUG:-false}" != "false" ]]; then
  echo "debug must be true or false" >&2
  exit 1
fi

printf '::add-mask::%s\n' "$INPUT_KIRO_API_KEY"
printf '::add-mask::%s\n' "$INPUT_GITHUB_TOKEN"

event_details="$(
  python3 - "$GITHUB_EVENT_PATH" "$GITHUB_EVENT_NAME" "${INPUT_TRIGGER_PHRASE:-@kiro}" <<'PY'
import json
import sys

path, event_name, trigger_phrase = sys.argv[1:]
with open(path, encoding="utf-8") as event_file:
    event = json.load(event_file)

repository = event.get("repository", {}).get("full_name", "")
if event_name == "pull_request":
    pull_request = event.get("pull_request") or {}
    number = pull_request.get("number") or event.get("number")
    if not repository or not number:
        values = ("skip", "", "", "event does not identify a pull request")
    else:
        values = ("run", repository, number, "pull_request")
elif event_name == "issue_comment":
    issue = event.get("issue") or {}
    comment = event.get("comment") or {}
    body = comment.get("body") or ""
    association = (comment.get("author_association") or "").upper()
    trusted = {"OWNER", "MEMBER", "COLLABORATOR"}
    if not issue.get("pull_request"):
        values = ("skip", repository, issue.get("number", ""), "comment is not attached to a pull request")
    elif trigger_phrase.lower() not in body.lower():
        values = ("skip", repository, issue.get("number", ""), "comment does not contain the trigger phrase")
    elif association not in trusted:
        values = ("skip", repository, issue.get("number", ""), "comment author is not trusted")
    else:
        values = ("run", repository, issue.get("number", ""), "issue_comment")
else:
    values = ("skip", repository, "", "unsupported event")

print("\t".join(str(value).replace("\t", " ").replace("\n", " ") for value in values))
PY
)"

IFS=$'\t' read -r DECISION REPOSITORY PR_NUMBER TRIGGER <<< "$event_details"
readonly DECISION REPOSITORY PR_NUMBER TRIGGER

if [[ "$DECISION" != "run" ]]; then
  skip "$TRIGGER"
fi
if [[ -z "$REPOSITORY" || -z "$PR_NUMBER" ]]; then
  echo "GitHub event is missing repository or pull-request information" >&2
  exit 1
fi

work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/kiro-cost-review.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

curl --fail --silent --show-error --location \
  --header "Authorization: Bearer $INPUT_GITHUB_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --header "Accept: application/vnd.github.v3.diff" \
  "${GITHUB_API_URL:-https://api.github.com}/repos/$REPOSITORY/pulls/$PR_NUMBER" \
  --output "$work_dir/pull-request.diff"

diff_size="$(wc -c < "$work_dir/pull-request.diff" | tr -d '[:space:]')"
if (( diff_size > INPUT_MAX_DIFF_SIZE )); then
  echo "Pull-request diff is ${diff_size} bytes; max_diff_size is ${INPUT_MAX_DIFF_SIZE}" >&2
  exit 1
fi

export PATH="$HOME/.local/bin:$HOME/.kiro/bin:$PATH"
if ! command -v kiro-cli >/dev/null 2>&1; then
  curl --fail --silent --show-error --location https://cli.kiro.dev/install \
    --output "$work_dir/install-kiro.sh"
  bash "$work_dir/install-kiro.sh"
fi
if ! command -v kiro-cli >/dev/null 2>&1; then
  echo "Kiro CLI installation completed but kiro-cli is not on PATH" >&2
  exit 1
fi
kiro-cli settings app.disableAutoupdates true >/dev/null
printf 'Using %s\n' "$(kiro-cli --version)"

mkdir -p "$HOME/.kiro/agents" "$HOME/.kiro/settings" "$HOME/.kiro/steering"
cp "$GITHUB_ACTION_PATH/reviewer/code-reviewer.json" "$HOME/.kiro/agents/code-reviewer.json"
cp "$GITHUB_ACTION_PATH/reviewer/cost-review-rubric.md" "$HOME/.kiro/agents/cost-review-rubric.md"
cat > "$HOME/.kiro/settings/mcp.json" <<EOF
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": [
        "run",
        "--interactive",
        "--rm",
        "--env",
        "GITHUB_PERSONAL_ACCESS_TOKEN",
        "$GITHUB_MCP_IMAGE"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "\${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
EOF

export KIRO_API_KEY="$INPUT_KIRO_API_KEY"
export GITHUB_PERSONAL_ACCESS_TOKEN="$INPUT_GITHUB_TOKEN"

prompt=$(printf 'Repository: %s\nPull request: #%s\nTrigger: %s\nUse the GitHub MCP tools and complete the configured cost-review task now.' \
  "$REPOSITORY" "$PR_NUMBER" "$TRIGGER")

set +e
kiro-cli chat --v3 \
  --agent code-reviewer \
  --no-interactive \
  --trust-all-tools \
  --require-mcp-startup \
  --output-format stream-json \
  "$prompt" > "$work_dir/kiro-output.jsonl" 2>&1
kiro_status=$?
set -e

if [[ "$INPUT_DEBUG" == "true" ]]; then
  cat "$work_dir/kiro-output.jsonl"
fi

case "$kiro_status" in
  0)
    echo "Kiro cost review completed for $REPOSITORY#$PR_NUMBER"
    write_conclusion "success"
    ;;
  3)
    echo "GitHub MCP server failed to start; rerun with debug: true for details" >&2
    exit 3
    ;;
  4)
    echo "Bundled code-reviewer agent could not be loaded" >&2
    exit 4
    ;;
  *)
    echo "Kiro CLI failed with exit code $kiro_status; rerun with debug: true for details" >&2
    exit "$kiro_status"
    ;;
esac
