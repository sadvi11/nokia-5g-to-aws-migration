# =============================================================================
# Module 01: VPC Data Plane — Nokia UPF (User Plane Function) Equivalent
# =============================================================================
#
# Nokia UPF: The ONLY data-plane component in 5G Core. Performs GTP-U
# tunneling, packet forwarding, NAT (CGNAT), DPI, QoS enforcement,
# and usage reporting. Anchors subscriber sessions during mobility.
# Source: 3GPP TS 23.501, Section 6.2.3
#
# AWS Mapping:
#   UPF packet forwarding  → VPC routing tables
#   UPF CGNAT              → NAT Gateway
#   UPF GTP-U tunneling    → VPC Endpoints (private connectivity)
#   UPF QoS enforcement    → Security Groups + NACLs
#   UPF multi-zone deploy  → Multi-AZ subnets
#
# Design decisions from Nokia carrier-grade ops:
#   - 3 AZs minimum (N+1 redundancy, same as Nokia cloud zones)
#   - Private subnets for all workloads (UPF internal interfaces are never public)
#   - NAT Gateway per AZ (avoids cross-AZ single point of failure)
#   - VPC Flow Logs enabled (equivalent to UPF usage reporting)
# =============================================================================

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name          = "${var.project_name}-${var.environment}-vpc"
    NokiaMapping  = "UPF-DataPlane"
    Description   = "Data plane network - maps to Nokia UPF forwarding domain"
  }
}

# --- Internet Gateway (N6 interface equivalent: UPF → Data Network) ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name         = "${var.project_name}-${var.environment}-igw"
    NokiaMapping = "UPF-N6-Interface"
    Description  = "External connectivity - maps to Nokia UPF N6 interface to DN"
  }
}

# --- Public Subnets (N2/N3 interface zone: external-facing) ---
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name         = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
    NokiaMapping = "N2-N3-ExternalZone"
    Tier         = "public"
  }
}

# --- Private Subnets (SBI zone: internal service communication) ---
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name         = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
    NokiaMapping = "SBI-InternalZone"
    Tier         = "private"
  }
}

# --- Elastic IPs for NAT Gateways ---
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${var.availability_zones[count.index]}"
  }
}

# --- NAT Gateways (UPF CGNAT equivalent: address translation) ---
# One per AZ to avoid cross-AZ dependency — learned from Nokia UPF zone isolation
resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name         = "${var.project_name}-${var.environment}-nat-${var.availability_zones[count.index]}"
    NokiaMapping = "UPF-CGNAT"
    Description  = "NAT per AZ - maps to Nokia UPF CGNAT function per cloud zone"
  }

  depends_on = [aws_internet_gateway.main]
}

# --- Route Tables ---

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-public-rt"
    NokiaMapping = "N6-Routing"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables (one per AZ, routes through local NAT Gateway)
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-private-rt-${var.availability_zones[count.index]}"
    NokiaMapping = "SBI-InternalRouting"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- VPC Flow Logs (UPF Usage Reporting equivalent) ---
# Nokia UPF reports per-session usage to CHF. VPC Flow Logs capture all traffic.
resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = {
    Name         = "${var.project_name}-${var.environment}-flow-logs"
    NokiaMapping = "UPF-UsageReporting"
    Description  = "Traffic logging - maps to Nokia UPF usage reports to CHF"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.project_name}-${var.environment}/flow-logs"
  retention_in_days = 90

  tags = {
    NokiaMapping = "UPF-CDR-Storage"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-${var.environment}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-${var.environment}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
