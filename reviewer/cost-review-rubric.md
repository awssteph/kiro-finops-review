# AWS Cost-Optimization Review Rubric

Review only the pull-request diff. Do not access live AWS accounts. Comment only on
cost. For each finding, state what to flag, a concrete fix, and a trade-off to validate.
For infrastructure-as-code or configuration findings, include a syntactically valid,
directly applicable fenced code snippet in the source language.

## Compute architecture

Flag EC2, Lambda, ECS/Fargate, RDS, ElastiCache, or OpenSearch using x86 instance
families when an arm64 equivalent exists. Recommend Graviton equivalents or Lambda
`arm64`. Confirm runtimes, images, native dependencies, and performance support arm64.

## Rightsizing

Flag instance sizes, task CPU or memory, provisioned capacity, or replica counts that
appear oversized or are hard-coded maximums. Recommend the smallest configuration that
meets measured utilization and peak/failover headroom.

## Elasticity and pricing models

Flag fixed fleets without autoscaling, on-demand pricing for durable baseline load, and
fault-tolerant batch workloads using only on-demand capacity. Recommend autoscaling,
Spot for interruption-tolerant work, and commitments only for a measured stable baseline.

## Lambda memory

Flag memory settings without a tuning rationale. Recommend Lambda Power Tuning and the
memory level that minimizes cost times duration. Validate latency because reducing
memory can increase duration and total cost.

## S3 lifecycle and Intelligent-Tiering

Flag buckets without lifecycle rules, expiration for logs or old versions, or tiering
for variable access. Recommend appropriate transitions, expiration, aborted multipart
upload cleanup, and Intelligent-Tiering for unknown access patterns. For CloudFormation,
show a `LifecycleConfiguration` block placed under the affected bucket's `Properties`.
Validate retrieval latency, minimum-duration charges, and per-object monitoring fees.

## EBS gp3

Flag `gp2`, or `io1` without a demonstrated need. Recommend `gp3` and independently
provisioned IOPS and throughput. Validate that the settings replace prior burst behavior.

## DynamoDB capacity and table class

Flag on-demand mode for predictable steady traffic, fixed provisioned capacity for
spiky traffic, or Standard-IA for frequently accessed tables. Recommend provisioned
capacity with autoscaling for predictable traffic, on-demand for unknown traffic, and
Standard-IA only for infrequently accessed data. Validate read and write costs.

## OpenSearch standby replicas

Flag Multi-AZ with Standby when the additional reserved capacity is not required.
Recommend sizing nodes and replicas to the availability objective. Validate the SLA and
failover requirement before reducing standby capacity.

## CloudWatch Logs

Flag unlimited retention, verbose production logging, or Standard log class for
high-volume logs that are rarely queried. Recommend finite retention, appropriate log
levels, and Infrequent Access where supported. Validate compliance and debugging needs.

## Bedrock model and token sizing

Flag oversized context, unbounded output tokens, or a large model for a simple task.
Recommend trimming context, limiting output, prompt caching where appropriate, and the
smallest model meeting measured quality. Validate changes against evaluations.

## Networking

Flag unnecessary NAT Gateway duplication, NAT paths where VPC endpoints are suitable,
or chatty cross-AZ traffic. Recommend endpoints, consolidation where resilience permits,
and deliberate placement. Validate availability before reducing AZ isolation.
