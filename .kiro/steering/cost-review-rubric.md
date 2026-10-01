---
inclusion: manual
---

# AWS Cost-Optimization Review Rubric

Static review of the PR diff only. No live AWS credentials. Comment only on cost;
if nothing in the diff has cost implications, pass. For every finding give:
**what to flag -> concrete fix -> trade-off to validate**.

## Compute architecture (Graviton / arm64)

- **Flag:** EC2, Lambda, ECS/Fargate, RDS, ElastiCache, or OpenSearch using x86
  instance families (e.g. `m5`, `c5`, `r5`, `t3`) where an arm64 equivalent exists.
- **Fix:** Move to Graviton equivalents (`m7g`/`c7g`/`r7g`, `t4g`, Lambda
  `arm64` architecture, Fargate `runtimePlatform` ARM64).
- **Trade-off:** Confirm the runtime/base image and all native dependencies have
  arm64 builds; validate performance for the workload.

## Rightsizing

- **Flag:** Instance sizes, task CPU/memory, provisioned capacity, or replica
  counts that look larger than the workload needs or hard-coded "safe" maximums.
- **Fix:** Drop to the smallest size that meets utilization targets; right-size
  task CPU/memory; reduce replica/node counts.
- **Trade-off:** Validate against observed CPU/memory/throughput and headroom for
  peak and failover.

## Elasticity & pricing models (autoscaling / Spot / Savings Plans)

- **Flag:** Fixed-size fleets with no autoscaling; on-demand pricing for steady
  baseline load; batch/stateless/fault-tolerant workloads on on-demand.
- **Fix:** Add autoscaling to track demand; use Spot for interruption-tolerant
  work; cover steady baseline with Savings Plans / Reserved Instances.
- **Trade-off:** Spot needs interruption handling; commitments reduce flexibility —
  confirm the baseline is durable before committing.

## Lambda memory

- **Flag:** Lambda `MemorySize` set well above or below need; no tuning rationale.
- **Fix:** Right-size memory (CPU scales with memory) using Lambda Power Tuning;
  pick the memory that minimizes cost x duration.
- **Trade-off:** Lower memory can raise duration (and cost) and latency; validate
  the duration/latency curve, not just the per-ms price.

## S3 lifecycle & Intelligent-Tiering

- **Flag:** Buckets with no lifecycle rules; objects staying in STANDARD when
  access tapers; no transition/expiration for logs or old versions.
- **Fix:** Add lifecycle rules (transition to IA / Glacier tiers, expire old
  versions and incomplete multipart uploads); use Intelligent-Tiering for
  unknown/variable access patterns.
- **Trade-off:** Retrieval latency/cost for colder tiers; Intelligent-Tiering has
  a small monitoring fee — confirm access pattern and minimum-duration charges.

## EBS gp3

- **Flag:** EBS volumes using `gp2` (or io1 where not needed).
- **Fix:** Migrate to `gp3` (cheaper per GB, baseline 3000 IOPS / 125 MB/s with
  independently provisioned throughput).
- **Trade-off:** Validate required IOPS/throughput are provisioned on gp3 to match
  prior gp2 burst behavior.

## DynamoDB capacity mode & table class

- **Flag:** On-demand mode for predictable steady traffic (or provisioned for
  spiky/unknown traffic without autoscaling); Standard-IA table class applied to
  hot/frequently-read tables.
- **Fix:** Use provisioned + autoscaling for predictable load, on-demand for spiky/
  unknown load; use Standard-IA only for infrequently accessed data. Keep hot,
  frequently-read tables on the STANDARD table class.
- **Trade-off:** Standard-IA has cheaper storage but higher read/write costs — only
  worth it when access is genuinely infrequent; validate the traffic profile.

## OpenSearch standby replicas

- **Flag:** Multi-AZ with Standby enabled where the extra reserved standby capacity
  is not required.
- **Fix:** Disable standby replicas when not needed; size data nodes to the actual
  availability requirement.
- **Trade-off:** Standby improves availability/failover — confirm the SLA before
  removing it.

## CloudWatch Logs retention, class & level

- **Flag:** Log groups with no retention (never expire); verbose DEBUG logging in
  production; Standard log class for logs that are rarely queried.
- **Fix:** Set a finite retention policy; raise log level to INFO/WARN in prod;
  use the Infrequent Access log class for high-volume, rarely-queried logs.
- **Trade-off:** Shorter retention and IA class reduce queryability/features;
  confirm compliance/debugging needs first.

## Bedrock prompt / token / model sizing

- **Flag:** Oversized prompts/context, unbounded `max_tokens`, or a large flagship
  model used for simple tasks.
- **Fix:** Trim prompt/context, cap output tokens, and select the smallest model
  that meets quality (e.g. Haiku/Nova-tier for simple tasks); cache/reuse context.
- **Trade-off:** Smaller models/shorter context may lower answer quality — validate
  against evaluation criteria.

## Networking (NAT Gateway & cross-AZ transfer)

- **Flag:** One NAT Gateway per AZ when traffic is low (or NAT where a VPC endpoint
  would do); architectures that force cross-AZ data transfer for chatty traffic.
- **Fix:** Consolidate NAT Gateways where resilience allows; add VPC/Gateway
  endpoints (S3, DynamoDB) to avoid NAT; co-locate chatty components in one AZ.
- **Trade-off:** Fewer NAT Gateways reduces AZ isolation; single-AZ co-location
  trades availability for lower transfer cost — confirm the resilience requirement.
