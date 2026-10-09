# ARC319 Live Demo — Build and Use Kiro FinOps Review

## Part 1 — Show the action you own

Open these files in order:

1. `action.yml` — the GitHub Marketplace contract and public inputs.
2. `scripts/run-review.sh` — your implementation: event validation, Kiro installation,
   GitHub MCP configuration, and headless agent invocation.
3. `reviewer/code-reviewer.json` — the Kiro review behavior and GitHub tool boundary.
4. `reviewer/cost-review-rubric.md` — the AWS cost knowledge shipped with the action.

The consumer workflow calls your immutable release directly:

```yaml
- name: Kiro FinOps review
  uses: awssteph/kiro-finops-review@v1.0.0
  with:
    kiro_api_key: ${{ secrets.KIRO_API_KEY }}
    github_token: ${{ github.token }}
    max_diff_size: 20000
```

There is no dependency on another review action. Kiro CLI and the official GitHub MCP
server remain runtime tools used by your implementation.

## Part 2 — Publish it

1. Validate the action locally.
2. Commit and push the repository.
3. Create a GitHub release tagged `v1.0.0`.
4. Select **Publish this Action to the GitHub Marketplace** on the release page.
5. Choose **Code quality** and publish using two-factor authentication.

The workflow cannot resolve `awssteph/kiro-finops-review@v1.0.0` until the release tag
exists remotely.

## Part 3 — Trigger the S3 review

`s3_intelligent_tiering.yaml` contains a deliberate cost concern: an S3 bucket without
lifecycle rules or Intelligent-Tiering.

1. Create a branch containing the S3 change and open a PR against `main`.
2. The `pull_request` trigger runs `awssteph/kiro-finops-review@v1.0.0`.
3. The bundled reviewer posts a cost finding on `AnalyticsDataBucket` covering the
   storage impact, concrete fix, and trade-off.
4. Push another commit to demonstrate the `synchronize` trigger.
5. Comment `@kiro review this again` as an owner, member, or collaborator to demonstrate
   the trusted comment trigger.

## Part 4 — Edit the Kiro behavior

Change `reviewer/cost-review-rubric.md` or `reviewer/code-reviewer.json`, validate it,
and publish a new immutable semantic release. Consumer pull requests cannot replace
these files because the runner loads them from the released action directory rather
than the PR.
