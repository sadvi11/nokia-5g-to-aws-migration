# =============================================================================
# Production Environment Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ca-central-1"
}

variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "nokia-5g-aws"
}

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  default     = "prod"
}

# -----------------------------------------------------------------------------
# VPC / Data Plane (Nokia UPF equivalent)
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC. Nokia equivalent: UPF data plane addressing."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs for multi-zone deployment. Nokia equivalent: 3 cloud zones for N+1 redundancy."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (ALB, NAT Gateway). Nokia equivalent: N2/N3 interface endpoints."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (ECS tasks, DynamoDB). Nokia equivalent: internal SBI network."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# -----------------------------------------------------------------------------
# ECS / Container Orchestration (Nokia CBAM equivalent)
# -----------------------------------------------------------------------------
variable "container_image" {
  description = "Docker image URI for the application"
  type        = string
  default     = "nginx:latest" # Replace with your ECR image
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "ecs_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Memory (MiB) for ECS task"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks. Nokia equivalent: CNF instance pool size."
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Kinesis / Event Bus (Nokia OAM equivalent)
# -----------------------------------------------------------------------------
variable "kinesis_shard_count" {
  description = "Number of Kinesis shards. Nokia equivalent: OAM event bus partitions."
  type        = number
  default     = 2
}

variable "kinesis_retention_hours" {
  description = "Event retention in hours. Nokia equivalent: OAM event buffer duration."
  type        = number
  default     = 48
}
