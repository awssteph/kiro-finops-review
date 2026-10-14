# ARC319 Live Demo — Add Kiro FinOps Review to CI


## 1. Show the Kiro action repository

Open these files in order.

### `action.yml`

**Say:**

> This is the public contract for our GitHub Action. A consumer provides a Kiro API key and the GitHub token already available to the workflow. The released `v1.0.2` tag makes this version repeatable.

Point out:

- `kiro_api_key` authenticates Kiro CLI.
- `github_token` reads the pull request and posts review comments.
- `max_diff_size` limits how much untrusted pull-request content is reviewed.
- `debug` is off by default because raw output can include source content.

### `reviewer/code-reviewer.json`

**Say:**

> This custom Kiro agent defines the review behavior and limits the agent to GitHub MCP tools. It can create a cost review or answer a trusted question, but it never approves a pull request.

### `reviewer/cost-review-rubric.md`

**Say:**

> This rubric gives the agent a focused definition of a useful FinOps finding: identify the resource, explain the cost impact, recommend a concrete change, and include a trade-off to validate.

## 2. Show what existed before Kiro

Open `riv26_arch319_code_examples/demo-assets/main.yaml`.

**Say:**

> We already have normal CI. `cfn-lint` checks that the CloudFormation template is structurally valid. That is necessary, but valid infrastructure can still be unnecessarily expensive.


**Say:**

> We keep the existing lint job and add a separate Kiro review job. The application code does not change, and the consumer only adds one released action.

Add three things to the existing workflow.

1. Add the optional comment trigger:

```yaml
issue_comment:
  types: [created]
pull_request_review_comment:
  types: [created]
```

2. Run lint only for pull-request events:

```yaml
lint:
  if: github.event_name == 'pull_request'
```

3. Add the Kiro review job:

```yaml
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
  permissions:
    contents: read
    pull-requests: write
    issues: write
  runs-on: ubuntu-latest
  timeout-minutes: 15
  steps:
    - name: Run Kiro FinOps review
      uses: awssteph/kiro-finops-review@v1.0.2
      with:
        kiro_api_key: ${{ secrets.KIRO_API_KEY }}
        github_token: ${{ github.token }}
```

**Say:**

> push this to main  changes run lint and cost review. Trusted `@kiro` comments can request a follow-up. Only the review job gets write access, and fork pull requests do not receive the Kiro secret. The Kiro job needs no checkout because it reads the PR through GitHub.

## 3. Create branch then add s£

Open `cloudformation/s3_bucket.yaml`.

**Say:**

> This bucket is valid CloudFormation, so lint passes. However, analytics data with changing access patterns remains in S3 Standard forever. A syntax checker cannot decide whether that storage design is cost-efficient.

For the review demo, `cloudformation/s3_bucket.yaml` must be a **newly added file** in the pull-request diff. Copy it from `demo-assets/s3_bucket.yaml` and leave the demo asset in place. Do not move or rename the demo asset: GitHub will classify a content-identical move as a rename with no added infrastructure lines for the diff-only reviewer to assess.


## 4. Trigger the finding

Open a pull request that adds `cloudformation/s3_bucket.yaml` as a new file. Keep `demo-assets/s3_bucket.yaml` in place so GitHub does not collapse the change into a rename.
This takes a while so lets go to one we ran earlier. 

**Say:**

> Both checks inspect the same change for different reasons. Lint verifies correctness. Kiro reviews the architectural cost implication.

Show:

1. The passing `cfn-lint` job.
2. The Kiro review on `AnalyticsDataBucket`.
3. The explanation of storage impact, recommended change, and trade-off.


the completed workflow is already on the repository's default branch, comment:

```text
@kiro review this again
```

**Say:**

> Trusted repository collaborators can request another review without changing code. Untrusted comments are ignored.

To demonstrate question mode, comment:

```text
@kiro what trade-off should I validate for this lifecycle change?
```

**Say:**

> The same custom agent can answer one focused pull-request question instead of creating another formal review.

## Close

**Say:**

> We started with conventional validation and added an architecture-aware FinOps review as one reusable action. The action performs static review through GitHub; it does not inspect or modify a deployed AWS environment.
