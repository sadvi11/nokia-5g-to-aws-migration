# High Availability Patterns: Nokia Carrier-Grade → AWS Fintech

> Four HA patterns learned from operating Nokia 5G Core at carrier scale (10M+ subscribers, five-nines SLA), translated to AWS for fintech/mortgage processing platforms.

---

## Pattern 1: Stateless Control Plane, Persistent Data Plane

### Nokia 5G
AMF and SMF pods are stateless. Subscriber context (authentication vectors, session state, subscription data) lives in UDM. If an AMF pod crashes, the replacement pod reads subscriber context from UDM — **no session dropped**.

Nokia design principle: "NFs are cattle, UDM is a pet."

### AWS Translation
ECS tasks (Lambda functions) are stateless. State lives in DynamoDB. If a task crashes, ECS scheduler launches a replacement that reads state from DynamoDB.

**Implementation in this repo:**
- `modules/03-ecs-container-orchestration` → stateless Fargate tasks
- `modules/05-dynamodb-subscriber-store` → persistent state store with PITR

**Interview soundbite:** *"At Nokia, we never stored session state in AMF pods — it all lived in UDM. I apply the same principle in AWS: ECS tasks are stateless, DynamoDB holds the state. If a task dies, the replacement picks up exactly where it left off."*

---

## Pattern 2: N+1 Active-Active, Never Active-Standby

### Nokia 5G
Nokia runs AMF pools at N+1 across 3+ cloud zones. All instances handle traffic simultaneously. If one fails, the remaining N instances absorb the load with no switchover delay.

Active-standby (2N) is explicitly avoided because:
- 50% capacity wasted (standby does nothing)
- Failover introduces delay (standby needs warmup)
- Failover logic itself is a failure point

### AWS Translation
Run minimum 3 ECS tasks across 3 AZs. ALB distributes traffic to all tasks (cross-zone enabled). If one task fails, ALB stops routing to it within seconds — no failover orchestration.

**Implementation in this repo:**
- `modules/02-alb-entry-point` → `enable_cross_zone_load_balancing = true`
- `modules/03-ecs-container-orchestration` → `min_capacity = 2`, spread across 3 AZs
- One NAT Gateway per AZ (module 01) avoids cross-AZ dependency

---

## Pattern 3: Graceful Degradation, Not Hard Failure

### Nokia 5G
When upgrading UPF, SMF sends an N4 Session Modification Request to drain active sessions to a new UPF instance. Only after all sessions are drained does the old UPF pod receive SIGTERM. **Zero in-flight sessions are dropped during upgrades.**

This is the hardest operational pattern to get right at carrier scale.

### AWS Translation
ALB deregistration delay (30s) + ECS task `stopTimeout`. When a task is being replaced:
1. ALB stops sending new requests to the task
2. In-flight requests have 30s to complete
3. ECS sends SIGTERM after deregistration completes
4. Task has `stopTimeout` seconds for cleanup

**Implementation in this repo:**
- `modules/02-alb-entry-point` → `deregistration_delay = 30`
- `modules/03-ecs-container-orchestration` → `minimum_healthy_percent = 100` (never below desired count)

---

## Pattern 4: Isolation Boundaries Prevent Blast Radius

### Nokia 5G
Network slicing (NSSF + end-to-end) creates isolated virtual networks on shared physical infrastructure. Each slice has dedicated:
- Resource quotas (CPU, memory, bandwidth)
- QoS policies (latency, throughput guarantees)
- SLA targets (independent of other slices)

A traffic spike in the eMBB slice (high-throughput mobile broadband) **cannot starve** the URLLC slice (ultra-reliable low-latency for industrial automation).

### AWS Translation
- Separate VPCs per environment (dev/staging/prod)
- Security Groups restrict inter-service communication
- ECS task resource limits prevent noisy neighbour
- Reserved Lambda concurrency for critical paths

**Implementation in this repo:**
- `modules/01-vpc-data-plane` → isolated VPC with public/private separation
- `modules/03-ecs-container-orchestration` → hard CPU/memory limits per task
- `modules/07-compliance-policy` → Security Group rules enforced by Config
