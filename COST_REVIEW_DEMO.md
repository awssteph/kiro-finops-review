# Automated AWS Cost-Optimization Reviews on Pull Requests

This repository contains the **Kiro FinOps Review** GitHub Action. It does not use
another review action. When a pull request is opened, updated, or marked ready, the
bundled Kiro agent reads the diff through GitHub MCP and posts an inline cost review.
No AWS credentials are involved.

## Execution flow

```text
PR event or trusted @kiro comment
              |
              v
 awssteph/kiro-finops-review@v1.0.0
              |
              +-- validate event and author
              +-- reject oversized diffs
              +-- install Kiro CLI
              +-- start official GitHub MCP server
              +-- load bundled agent and cost rubric
              |
              v
       GitHub PR review/comments
```

The action implementation consists of:

1. `action.yml` — Marketplace metadata, inputs, outputs, and composite entry point.
2. `scripts/run-review.sh` — event filtering, setup, and Kiro CLI invocation.
3. `reviewer/code-reviewer.json` — the trusted dual-mode Kiro agent.
4. `reviewer/cost-review-rubric.md` — the AWS cost-review criteria.

The released copies under `reviewer/` are installed into the runner's global Kiro
configuration. They are never loaded from the pull-request branch, so a PR cannot edit
its own reviewer.

## Reviewer behavior

On a pull-request event, the agent reviews only cost implications. It fetches the diff
and changed files through GitHub MCP, creates a pending review, adds inline comments,
and submits the review as `COMMENT`. If it finds no cost concern, it submits a short
no-cost-concerns review.

On a trusted PR comment containing `@kiro`, the agent answers a substantive question or
runs another review when the comment only requests review. Both the workflow and action
accept comment triggers only from `OWNER`, `MEMBER`, or `COLLABORATOR` associations.

Each cost finding identifies the affected resource or line, explains the likely cost
impact, recommends a concrete fix, and states a trade-off to validate. Covered areas
include Graviton, rightsizing, autoscaling and pricing models, Lambda memory, S3 storage,
EBS gp3, DynamoDB capacity and table class, OpenSearch standby capacity, CloudWatch Logs,
Bedrock model and token sizing, and network transfer paths.

## Setup

Add `KIRO_API_KEY` as a repository Actions secret, then use the immutable release:

```yaml
- name: Kiro FinOps review
  uses: awssteph/kiro-finops-review@v1.0.0
  with:
    kiro_api_key: ${{ secrets.KIRO_API_KEY }}
    github_token: ${{ github.token }}
    max_diff_size: 20000
```

Required workflow permissions are `contents: read`, `pull-requests: write`, and
`issues: write`. The action installs the current Kiro CLI from Kiro's official installer
and starts the pinned official GitHub MCP container. It fails if MCP startup or agent
loading fails instead of reporting a misleading successful run.

## Publishing

Commit and push the tested files, create the immutable `v1.0.0` GitHub release, select
the Marketplace publishing option, choose **Code quality**, and publish using two-factor
authentication. Consumers cannot resolve the action until that release tag exists.

## Demo finding

`s3_intelligent_tiering.yaml` intentionally defines an S3 bucket without lifecycle rules
or Intelligent-Tiering. A review should identify that Standard storage can retain cold
data indefinitely, recommend lifecycle transitions or Intelligent-Tiering, and mention
retrieval, minimum-duration, and monitoring-fee trade-offs.

For troubleshooting, set `debug: true` temporarily. Raw Kiro JSONL can include source
content, so disable it again after diagnosis.
