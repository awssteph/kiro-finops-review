# Automated AWS Cost-Optimization Reviews on Pull Requests

This repo runs a **static, diff-only AWS cost review** on every pull request using the
[Kiro CLI Review Action](https://github.com/marketplace/actions/kiro-cli-review-action)
(`konippi/kiro-cli-review-action@v1`). When a PR is opened, a Kiro agent reads the diff,
checks it against a cost rubric, and posts inline review comments on anything that
introduces avoidable cloud spend — no AWS credentials involved.

---

## Why

Cost regressions are easy to merge and hard to notice: a `gp2` volume, an x86 instance
family, an S3 bucket with no lifecycle policy. They don't break the build, so nothing
flags them. This action puts a cost reviewer in the PR itself, as a comment, before merge.

Key design choice: **static review only.** The review reasons about the *diff text*. It
does **not** connect to your AWS account, does **not** read Cost Explorer or CloudWatch,
and needs **no AWS credentials in CI**. The only secret required is a Kiro API key.

---

## How it works

```
PR opened / "ready for review"          ┌─────────────────────────────┐
   │  (or an @kiro comment)             │  GitHub Actions runner      │
   ▼                                    │                             │
GitHub Actions trigger ───────────────▶ │  1. checkout PR head        │
                                        │  2. install kiro-cli +      │
                                        │     github-mcp-server       │
                                        │  3. run "code-reviewer"     │
                                        │     agent over the diff     │
                                        └──────────────┬──────────────┘
                                                       │ @github MCP tools
                                                       ▼
                                        Inline review comments on the PR
```

1. **Trigger** — `pull_request` (`opened`, `ready_for_review`) or an `@kiro` PR comment.
2. **Checkout** — the action checks out the PR head commit.
3. **Agent run** — it installs `kiro-cli` and `github-mcp-server`, then runs our custom
   `code-reviewer` agent. The agent fetches the diff through the GitHub MCP server,
   evaluates it against the rubric, and posts a `COMMENT` review with inline comments.
4. **Security** — the action **ignores PR-authored changes under `.kiro/`**. It restores
   `.kiro/` from the **base branch** before running, so a PR can't rewrite the reviewer
   to weaken or disable it. This is why the agent config must live on the default branch.

---

## The three files

### 1. `.github/workflows/kiro-cost-review.yml` — the workflow

```yaml
on:
  pull_request:
    types: [opened, ready_for_review]
  issue_comment:
    types: [created]        # lets you re-trigger by commenting @kiro

permissions:
  contents: read
  pull-requests: write      # post review comments
  issues: write             # needed for the comment trigger

jobs:
  cost-review:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ github.event.pull_request.head.sha || '' }}
      - uses: konippi/kiro-cli-review-action@v1
        with:
          kiro_api_key: ${{ secrets.KIRO_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}   # REQUIRED — see "gotcha" below
          agent: code-reviewer
          max_diff_size: 20000
```

### 2. `.kiro/agents/code-reviewer.json` — the agent

Defines **what tools the reviewer has** and **what it does**:

- `tools` / `allowedTools`: `fs_read`, `grep`, `glob`, `code`, and **`@github`**
  (the GitHub MCP toolset — `pull_request_read`, `pull_request_review_write`,
  `add_comment_to_pending_review`). Without `@github`, the agent can't post anything.
- `hooks.preToolUse`: blocks `fs_write` and `execute_bash` — the reviewer can read and
  comment, but never writes files or runs shell.
- `prompt`: an imperative, tool-first workflow — fetch the diff, open a pending review,
  add inline comments, submit as `COMMENT`. Always submit, even with zero findings.
- References the rubric in `.kiro/steering/cost-review-rubric.md`.

> No live-AWS MCP servers are configured. This keeps the review fully static and
> credential-free.

### 3. `.kiro/steering/cost-review-rubric.md` — the rubric

`inclusion: manual` steering file. Each cost area is written as
**what to flag → concrete fix → trade-off to validate**, covering:

Graviton/arm64 · rightsizing · elasticity (autoscaling/Spot/Savings Plans) ·
Lambda memory · S3 lifecycle & Intelligent-Tiering · EBS gp2→gp3 ·
DynamoDB capacity mode + Standard-IA table class (keep hot tables STANDARD) ·
OpenSearch standby replicas · CloudWatch Logs retention/log class/level ·
Bedrock prompt/token/model sizing · NAT Gateway sprawl & cross-AZ transfer.

---

## What a finding looks like

Demo PR: adding an S3 bucket with **no lifecycle rules and no Intelligent-Tiering**.
The reviewer posted an inline comment on the bucket, in the rubric's four-part format:

> **Cost finding — new `AnalyticsDataBucket` has no lifecycle or Intelligent-Tiering.**
>
> 1. **Resource/line:** `AnalyticsDataBucket`, S3 bucket with only `BucketEncryption`, no tiering.
> 2. **Cost impact:** objects stay in S3 Standard (~$0.023/GB-mo) indefinitely; cold data bills at full rate — at scale, hundreds of $/month of avoidable spend that only grows.
> 3. **Concrete fix:** enable S3 Intelligent-Tiering (right for *unpredictable* access) plus lifecycle rules to expire old versions and abort incomplete multipart uploads.
> 4. **Trade-off to validate:** Intelligent-Tiering has a small per-object monitoring fee — not economical for huge numbers of tiny objects; confirm object size distribution and that access is genuinely variable.

When a diff has **no** cost implications, it submits a short "no cost concerns" review
and moves on. It stays in scope — it does not comment on style or bugs.

---

## Setup checklist

1. **Add the `KIRO_API_KEY` repo secret** — *Settings → Secrets and variables → Actions*.
   Requires a Kiro Pro/Pro+/Power subscription. (`GITHUB_TOKEN` is provided automatically
   by Actions; the workflow just forwards it.)
2. **Keep `.kiro/agents/code-reviewer.json` on the default branch.** The action ignores
   PR edits to `.kiro/` for security, so the agent only takes effect from `main`.
3. **Open a PR** (or comment `@kiro` on an existing one) to trigger the review.

---

## The gotcha that cost us time (and the fix)

During setup, the review ran "successfully" but posted **nothing**. The logs showed
`Complete. Tool calls: 0` (later just local file reads) and the agent saying it had
*"no GitHub PR integration tool available."*

Root cause, from the ACP debug log:

```json
"env":[{"name":"GITHUB_PERSONAL_ACCESS_TOKEN","value":""}]
...
"_kiro.dev/mcp/server_init_failure","serverName":"github",
"error":"connection closed: initialize response"
"mcpServers":[{"name":"github","status":"failed","toolCount":0}]
```

The action launched `github-mcp-server` with an **empty token**, so the GitHub MCP
server failed to initialize and exposed **zero tools**. The agent could read the diff
locally but had no way to post a review.

**Fix:** pass the token explicitly in the workflow —

```yaml
github_token: ${{ secrets.GITHUB_TOKEN }}
```

After that, the agent's tool chain ran end to end:
`@github/pull_request_read` → `pull_request_review_write` (create pending) →
`add_comment_to_pending_review` → `pull_request_review_write` (submit COMMENT),
and the inline comment appeared on the PR.

**Lesson:** a green check only means the action didn't error — not that it posted a
review. Verify an actual comment lands, and if it doesn't, enable `debug: true` on the
action and read the ACP log for `server_init_failure` / `toolCount`.
