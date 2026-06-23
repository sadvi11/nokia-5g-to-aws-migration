# =============================================================================
# Nokia 5G Core → AWS Production Environment
# =============================================================================
# Each module maps to a Nokia 5G Core network function.
# See README.md for the complete architectural mapping.
#
# Nokia Component  → AWS Module             → Purpose
# ──────────────────────────────────────────────────────────────
# UPF (User Plane) → 01-vpc-data-plane      → Data plane networking
# AMF (Access Mgmt)→ 02-alb-entry-point     → Traffic entry + routing
# CBAM (App Mgr)   → 03-ecs-orchestration   → Container lifecycle
# OAM Event Bus    → 04-kinesis-event-bus    → Operational event streaming
# UDM (Data Mgmt)  → 05-dynamodb-store      → Subscriber/session state
# NRF (Repository) → 06-service-discovery   → Service registration/discovery
# PCF (Policy)     → 07-compliance-policy   → Runtime compliance enforcement
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # For production: uncomment and configure S3 backend
  # backend "s3" {
  #   bucket         = "nokia-5g-aws-tfstate"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ca-central-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "nokia-5g-to-aws-migration"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "sadhvi"
    }
  }
}

# =============================================================================
# Module 01: VPC Data Plane (Nokia UPF equivalent)
# UPF = User Plane Function: packet forwarding, NAT, QoS enforcement
# AWS  = VPC with public/private subnets, NAT Gateway, VPC Endpoints
# =============================================================================
module "vpc_data_plane" {
  source = "../../modules/01-vpc-data-plane"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# =============================================================================
# Module 02: ALB Entry Point (Nokia AMF equivalent)
# AMF = Access & Mobility Management: first signaling entry point, auth delegation
# AWS = Application Load Balancer: HTTPS termination, path routing, auth delegation
# =============================================================================
module "alb_entry_point" {
  source = "../../modules/02-alb-entry-point"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc_data_plane.vpc_id
  public_subnet_ids  = module.vpc_data_plane.public_subnet_ids
  health_check_path  = "/health"
}

# =============================================================================
# Module 03: ECS Container Orchestration (Nokia CBAM equivalent)
# CBAM = Cloud Band Application Manager: CNF lifecycle (deploy, scale, heal)
# AWS  = ECS Fargate: container lifecycle (deploy, scale, heal)
# =============================================================================
module "ecs_orchestration" {
  source = "../../modules/03-ecs-container-orchestration"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc_data_plane.vpc_id
  private_subnet_ids  = module.vpc_data_plane.private_subnet_ids
  alb_target_group_arn = module.alb_entry_point.target_group_arn
  alb_security_group_id = module.alb_entry_point.alb_security_group_id

  # Container config
  container_image     = var.container_image
  container_port      = var.container_port
  cpu                 = var.ecs_cpu
  memory              = var.ecs_memory
  desired_count       = var.ecs_desired_count

  # Nokia CBAM parallel: N+1 redundancy (minimum 2 tasks across AZs)
  min_capacity        = 2
  max_capacity        = 6

  # Service discovery namespace (NRF equivalent)
  service_discovery_namespace_id = module.service_discovery.namespace_id
}

# =============================================================================
# Module 04: Kinesis Event Bus (Nokia OAM Event Bus equivalent)
# OAM = Operations, Administration, Maintenance: fault/perf/config events
# AWS = Kinesis Data Streams: ordered, persistent, high-throughput event streaming
# =============================================================================
module "kinesis_event_bus" {
  source = "../../modules/04-kinesis-event-bus"

  project_name   = var.project_name
  environment    = var.environment
  shard_count    = var.kinesis_shard_count
  retention_hours = var.kinesis_retention_hours
}

# =============================================================================
# Module 05: DynamoDB Subscriber Store (Nokia UDM equivalent)
# UDM = Unified Data Management: subscriber profiles, session context
# AWS = DynamoDB: low-latency, highly available key-value store
# =============================================================================
module "dynamodb_store" {
  source = "../../modules/05-dynamodb-subscriber-store"

  project_name = var.project_name
  environment  = var.environment
}

# =============================================================================
# Module 06: Service Discovery (Nokia NRF equivalent)
# NRF = Network Repository Function: NF registration + discovery via Nnrf API
# AWS = Cloud Map: service registration + DNS-based discovery
# =============================================================================
module "service_discovery" {
  source = "../../modules/06-service-discovery"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc_data_plane.vpc_id
}

# =============================================================================
# Module 07: Compliance & Policy (Nokia PCF equivalent)
# PCF = Policy Control Function: QoS rules, gating decisions, charging triggers
# AWS = AWS Config + IAM + KMS: compliance rules, access policies, encryption
# =============================================================================
module "compliance_policy" {
  source = "../../modules/07-compliance-policy"

  project_name = var.project_name
  environment  = var.environment
}
