# =============================================================================
# Plan-only test harness
# =============================================================================
# This calls the SAME seven modules as environments/prod, with one difference:
# the provider skips credential validation, so `terraform plan` runs with no
# AWS account and no credentials.
#
# It exists as a separate root module rather than as flags on the production
# provider, because `skip_credentials_validation` on a config people might
# actually apply is a footgun - it turns a wrong-account mistake into a silent
# one. The production provider stays strict; only this harness is permissive.
#
# What a plan proves that `terraform validate` does not:
#   validate  - the configuration parses and types check
#   plan      - the modules actually compose, every reference resolves, and
#               these are the exact resources that would be created
#
# tests/architecture_test.py then asserts properties of the planned resources.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ca-central-1"

  # Plan without an AWS account. None of these weaken the modules under test -
  # they only stop the provider phoning STS before planning.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "test"
  secret_key                  = "test"

  default_tags {
    tags = {
      Project     = "nokia-5g-to-aws-migration"
      Environment = "test"
      ManagedBy   = "terraform"
      Owner       = "sadhvi"
    }
  }
}

locals {
  project_name = "nokia-5g-aws"
  environment  = "test"
}

# UPF - User Plane Function. Packet forwarding and the data plane.
module "vpc_data_plane" {
  source = "../modules/01-vpc-data-plane"

  project_name         = local.project_name
  environment          = local.environment
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# AMF - Access and Mobility Management. The entry point for signalling.
module "alb_entry_point" {
  source = "../modules/02-alb-entry-point"

  project_name      = local.project_name
  environment       = local.environment
  vpc_id            = module.vpc_data_plane.vpc_id
  public_subnet_ids = module.vpc_data_plane.public_subnet_ids
  health_check_path = "/health"
}

# NRF - Network Repository Function. Service registration and discovery.
module "service_discovery" {
  source = "../modules/06-service-discovery"

  project_name = local.project_name
  environment  = local.environment
  vpc_id       = module.vpc_data_plane.vpc_id
}

# CBAM - application lifecycle management.
module "ecs_orchestration" {
  source = "../modules/03-ecs-container-orchestration"

  project_name          = local.project_name
  environment           = local.environment
  vpc_id                = module.vpc_data_plane.vpc_id
  private_subnet_ids    = module.vpc_data_plane.private_subnet_ids
  alb_target_group_arn  = module.alb_entry_point.target_group_arn
  alb_security_group_id = module.alb_entry_point.alb_security_group_id

  container_image = "nginx:latest"
  container_port  = 8080
  cpu             = 512
  memory          = 1024
  desired_count   = 3

  min_capacity = 2
  max_capacity = 6

  service_discovery_namespace_id = module.service_discovery.namespace_id
}

# OAM event bus - operational telemetry streaming.
module "kinesis_event_bus" {
  source = "../modules/04-kinesis-event-bus"

  project_name    = local.project_name
  environment     = local.environment
  shard_count     = 2
  retention_hours = 48
}

# UDM - Unified Data Management. Subscriber and session state.
module "dynamodb_store" {
  source = "../modules/05-dynamodb-subscriber-store"

  project_name = local.project_name
  environment  = local.environment
}

# PCF - Policy Control Function. Runtime compliance enforcement.
module "compliance_policy" {
  source = "../modules/07-compliance-policy"

  project_name = local.project_name
  environment  = local.environment
}
