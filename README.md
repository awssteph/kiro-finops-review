# Kiro FinOps Review

A self-contained GitHub Action that uses Kiro CLI to review pull-request diffs for
AWS cost risks. The action is implemented in this repository and does not depend on
another review action.

It performs static analysis only: it reads the PR through GitHub's MCP server and does
not connect to AWS accounts or require AWS credentials.

## Usage

```yaml
name: Kiro FinOps Review

on:
  pull_request:
    types: [opened, ready_for_review, synchronize]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  review:
    if: >-
      (github.event_name == 'pull_request' &&
       github.event.pull_request.head.repo.full_name == github.repository) ||
      (github.event_name == 'issue_comment' &&
       github.event.issue.pull_request &&
       contains(github.event.comment.body, '@kiro') &&
       contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)) ||
      (github.event_name == 'pull_request_review_comment' &&
       contains(github.event.comment.body, '@kiro') &&
       contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association))
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: awssteph/kiro-finops-review@v1.0.2
        with:
          kiro_api_key: ${{ secrets.KIRO_API_KEY }}
          github_token: ${{ github.token }}
```

Add `KIRO_API_KEY` under **Settings → Secrets and variables → Actions**. API-key
authentication requires an eligible Kiro subscription.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `kiro_api_key` | Yes | — | Kiro CLI API key |
| `github_token` | Yes | — | Token used to read the PR and post comments |
| `trigger_phrase` | No | `@kiro` | Phrase accepted on trusted PR comments |
| `max_diff_size` | No | `20000` | Maximum diff size in bytes |
| `debug` | No | `false` | Print raw Kiro JSONL output; may expose source content |

The `conclusion` output is `success` or `skipped`. Execution errors fail the step.

## What ships in this action

- `action.yml` defines the Marketplace action and inputs.
- `scripts/run-review.sh` validates events, limits diff size, installs Kiro CLI,
  configures GitHub MCP, and invokes the reviewer.
- `reviewer/code-reviewer.json` is the trusted Kiro agent bundled with each release.
- `reviewer/cost-review-rubric.md` defines the AWS cost checks.

The bundled agent and rubric are loaded from the released action, not from the PR
branch. A pull request therefore cannot weaken its own reviewer. The action accepts
trusted `@kiro` questions from both the PR conversation and inline review threads;
answers are posted to the PR conversation. Only repository owners, members, and
collaborators can trigger comment handling.

The action installs the current Kiro CLI using Kiro's official Linux installer because
the public installer does not currently expose version selection. The official GitHub
MCP container is pinned in the runner script.

## Publish to GitHub Marketplace

1. Commit and push the tested action files to the public repository.
2. Create a GitHub release with the immutable tag `v1.0.2`.
3. Select **Publish this Action to the GitHub Marketplace** on the release page.
4. Choose the **Code quality** category and complete Marketplace validation.
5. Publish the release using two-factor authentication.

Workflows cannot use `awssteph/kiro-finops-review@v1.0.2` until that remote release tag
exists. Pinning consumers to a full commit SHA provides stronger immutable execution.

## Security notes

The action never executes files from the reviewed PR. It obtains the diff through the
GitHub API and runs an agent exposing only GitHub MCP tools. Forked PR workflows do not
normally receive repository secrets, so automatic reviews from forks require a separate,
carefully reviewed trust model. Keep `debug` disabled unless investigating a failure.

## Development validation

```bash
bash -n scripts/run-review.sh
python3 -m json.tool reviewer/code-reviewer.json >/dev/null
python3 -c 'import yaml; yaml.safe_load(open("action.yml"))'
```

See `COST_REVIEW_DEMO.md` for behavior and `demo.md` for the live demonstration flow.
