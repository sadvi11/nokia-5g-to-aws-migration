# Architecture Diagram: Nokia 5G Core → AWS

GitHub renders Mermaid diagrams natively. The diagram below shows every Nokia 5G network function mapped to its AWS equivalent, connected with accurate service relationships.

---

## Full architecture

```mermaid
flowchart TB
  Client(["Internet Client"])

  subgraph Entry ["Entry point — Nokia AMF → AWS ALB"]
    ALB["Application Load Balancer\n(HTTPS, multi-AZ, cross-zone)"]
    WAF["AWS WAF\n(L7 threat protection)"]
  end

  subgraph DataPlane ["Data plane — Nokia UPF → AWS VPC"]
    VPC["VPC\n(3 AZs, public + private subnets)"]
    NAT["NAT Gateway\n(per-AZ — CGNAT equivalent)"]
    FlowLogs["VPC Flow Logs\n(usage reporting to S3)"]
  end

  subgraph Orchestration ["Container orchestration — Nokia CBAM → ECS Fargate"]
    ECS["ECS Fargate Service\n(3 tasks, rolling deploy, min-healthy 100%)"]
    ASG["Application Auto Scaling\n(CPU + ALB request-count HPA)"]
    ECR["Amazon ECR\n(container image registry)"]
  end

  subgraph EventBus ["Event streaming — Nokia OAM bus → Kinesis"]
    Kinesis["Kinesis Data Streams\n(ordered per partition key, KMS encrypted)"]
    Lambda["Lambda consumer\n(FCAPS event processor)"]
  end

  subgraph DataStore ["Subscriber store — Nokia UDM → DynamoDB"]
    DDB["DynamoDB\n(on-demand, TTL, PITR, KMS encrypted)"]
  end

  subgraph Discovery ["Service discovery — Nokia NRF → Cloud Map"]
    CloudMap["AWS Cloud Map\n(private DNS namespace, ECS auto-register)"]
  end

  subgraph Policy ["Compliance policy — Nokia PCF → AWS Config"]
    Config["AWS Config\n(6 managed rules: PCI DSS + SOC 2)"]
    CloudTrail["CloudTrail\n(multi-region API audit trail)"]
    SecHub["Security Hub\n(findings aggregation + scoring)"]
  end

  Client --> WAF --> ALB
  ALB --> ECS
  ECS --> ECR
  ECS --> ASG
  ECS --> DDB
  ECS --> Kinesis
  ECS --> CloudMap
  Kinesis --> Lambda
  Lambda --> DDB
  VPC --> NAT
  VPC --> FlowLogs
  ECS -.->|"runs inside"| VPC
  Config --> SecHub
  CloudTrail --> Config
```

---

## Component mapping legend

| Subgraph colour | Nokia component | AWS service | Why the mapping is exact |
|---|---|---|---|
| Entry | AMF — first control-plane entry, auth delegation, routing | ALB + WAF | Both terminate external connections at L7, delegate auth, route to internal services |
| Data plane | UPF — packet forwarding, CGNAT, QoS enforcement | VPC + NAT Gateway + Flow Logs | Both are the data-plane layer: routing, address translation, traffic logging |
| Orchestration | CBAM — CNF lifecycle (deploy, scale, heal, upgrade) | ECS Fargate + Auto Scaling + ECR | Both manage container lifecycle: rolling deploys, HPA, health-check-driven healing |
| Event streaming | OAM event bus — FCAPS events, ordered per subscriber | Kinesis Data Streams + Lambda | Both provide ordered, persistent, high-throughput event streaming with consumer decoupling |
| Subscriber store | UDM — subscriber profiles, session context, auth data | DynamoDB | Both: low-latency reads, HA, stateless NFs/tasks read context from here on restart |
| Service discovery | NRF — NF registration + discovery via Nnrf API | AWS Cloud Map | Both: central registry, health-check-driven deregistration, DNS-based discovery |
| Compliance policy | PCF — PCC rules, gating decisions, policy enforcement | AWS Config + CloudTrail + Security Hub | Both enforce runtime compliance rules across all components and log violations |

---

## Data flow: request lifecycle

1. **Client → WAF** — L7 inspection, block malicious requests (Nokia: SEPP security edge equivalent)
2. **WAF → ALB** — HTTPS termination, auth delegation (Nokia: AMF N2 termination)
3. **ALB → ECS Fargate** — path-based routing to healthy task (Nokia: AMF → SMF routing)
4. **ECS → DynamoDB** — read/write session state (Nokia: SMF → UDM subscriber data)
5. **ECS → Kinesis** — publish operational events (Nokia: UPF/SMF → OAM event bus)
6. **Kinesis → Lambda** — consume and process FCAPS events (Nokia: CHF/NetAct consuming OAM)
7. **ECS → Cloud Map** — service registration on task startup (Nokia: NF → NRF registration)
8. **CloudTrail → Config** — API events feed compliance evaluation (Nokia: OAM → PCF policy input)
9. **Config → Security Hub** — aggregate findings, compute compliance score (Nokia: PCF → NOC dashboard)

---

*All Nokia component definitions sourced from 3GPP TS 23.501 and Nokia CloudBand documentation.*
*All AWS service descriptions sourced from AWS official documentation.*
