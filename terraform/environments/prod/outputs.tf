# =============================================================================
# Production Outputs
# =============================================================================

# --- VPC / Data Plane (Nokia UPF) ---
output "vpc_id" {
  description = "VPC ID (Nokia UPF data plane equivalent)"
  value       = module.vpc_data_plane.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Nokia internal SBI network equivalent)"
  value       = module.vpc_data_plane.private_subnet_ids
}

# --- ALB / Entry Point (Nokia AMF) ---
output "alb_dns_name" {
  description = "ALB DNS name (Nokia AMF N2 endpoint equivalent)"
  value       = module.alb_entry_point.alb_dns_name
}

# --- ECS / Container Orchestration (Nokia CBAM) ---
output "ecs_cluster_name" {
  description = "ECS cluster name (Nokia CBAM managed cluster equivalent)"
  value       = module.ecs_orchestration.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name (Nokia CNF instance pool equivalent)"
  value       = module.ecs_orchestration.service_name
}

# --- Kinesis / Event Bus (Nokia OAM) ---
output "kinesis_stream_name" {
  description = "Kinesis stream name (Nokia OAM event bus equivalent)"
  value       = module.kinesis_event_bus.stream_name
}

# --- DynamoDB / Subscriber Store (Nokia UDM) ---
output "dynamodb_table_name" {
  description = "DynamoDB table name (Nokia UDM subscriber data equivalent)"
  value       = module.dynamodb_store.table_name
}

# --- Service Discovery (Nokia NRF) ---
output "service_discovery_namespace" {
  description = "Cloud Map namespace (Nokia NRF registry equivalent)"
  value       = module.service_discovery.namespace_name
}
