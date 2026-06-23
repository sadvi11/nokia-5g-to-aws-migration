# =============================================================================
# Module 06: AWS Cloud Map — Nokia NRF (Network Repository Function) Equivalent
# =============================================================================
#
# Nokia NRF: Central service registry for the 5G Core SBA.
#   - All NF instances register their profiles via Nnrf_NFManagement
#   - Consumers discover producers via Nnrf_NFDiscovery
#   - NRF monitors NF health and deregisters unhealthy instances
#   - Supports NF type, capacity, service list, geographic info
#   Source: 3GPP TS 23.501 Section 6.2.6
#
# AWS Mapping:
#   NRF Nnrf_NFManagement  → Cloud Map RegisterInstance
#   NRF Nnrf_NFDiscovery   → Cloud Map DiscoverInstances / DNS lookup
#   NRF health monitoring  → Cloud Map custom health checks
#   NRF NF profile         → Cloud Map instance attributes
# =============================================================================

# --- Private DNS Namespace (Nokia NRF Registry) ---
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}.${var.environment}.local"
  description = "Service discovery namespace - Nokia NRF service registry equivalent"
  vpc         = var.vpc_id

  tags = {
    Name         = "${var.project_name}-${var.environment}-namespace"
    NokiaMapping = "NRF-ServiceRegistry"
    Description  = "DNS namespace - maps to Nokia NRF Nnrf service registry"
  }
}
