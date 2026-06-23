# =============================================================================
# Module 02: ALB Entry Point — Nokia AMF (Access & Mobility Mgmt) Equivalent
# =============================================================================
#
# Nokia AMF: First control-plane entry point for 5G Core.
#   - Terminates N2 (NGAP from gNB) and N1 (NAS from UE)
#   - Delegates authentication to AUSF/UDM
#   - Routes session requests to appropriate SMF based on DNN/S-NSSAI
#   - Runs as active-active pool across cloud zones (N+1 redundancy)
#   Source: 3GPP TS 23.501 Section 6.2.1
#
# AWS Mapping:
#   AMF N2 termination      → ALB HTTPS listener (Layer 7 termination)
#   AMF auth delegation      → ALB → Cognito integration (auth offload)
#   AMF → SMF routing        → ALB target group path-based routing
#   AMF active-active pool   → ALB cross-zone load balancing
#   AMF N+1 redundancy       → ALB multi-AZ with health checks
#
# Source: AWS ALB docs — "distributes traffic across multiple targets
#   in multiple Availability Zones, automatically routes to healthy targets"
# =============================================================================

# --- ALB Security Group (AMF access control equivalent) ---
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  description = "ALB security group - Nokia AMF N2 interface access control equivalent"
  vpc_id      = var.vpc_id

  # Inbound: HTTPS from internet (AMF N2 interface from gNB)
  ingress {
    description = "HTTPS from internet - maps to Nokia AMF N2 signaling ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound: HTTP redirect
  ingress {
    description = "HTTP for redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: to ECS tasks (AMF → SMF/UPF internal signaling)
  egress {
    description = "All outbound - maps to Nokia AMF Nsmf/Namf service calls"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-alb-sg"
    NokiaMapping = "AMF-N2-AccessControl"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Application Load Balancer (Nokia AMF Pool equivalent) ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Nokia AMF runs active-active across all cloud zones
  # ALB cross-zone = same pattern: distribute across all AZs evenly
  enable_cross_zone_load_balancing = true

  # Connection draining = Nokia UPF graceful session drain before pod termination
  # 30s matches typical request completion time
  enable_deletion_protection = false

  tags = {
    Name         = "${var.project_name}-${var.environment}-alb"
    NokiaMapping = "AMF-ActiveActivePool"
    Description  = "Entry point - maps to Nokia AMF pool (active-active, N+1)"
  }
}

# --- Target Group (Nokia SMF instance pool equivalent) ---
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for ECS Fargate

  # Health check = Nokia CBAM liveness probe equivalent
  # CBAM uses K8s liveness probes to detect unhealthy CNF pods
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  # Deregistration delay = Nokia UPF graceful session drain
  # When a CNF pod is being terminated, SMF signals UPF to drain active sessions
  # before Kubernetes sends SIGTERM. This is the AWS equivalent.
  deregistration_delay = 30

  tags = {
    Name         = "${var.project_name}-${var.environment}-tg"
    NokiaMapping = "SMF-InstancePool"
  }
}

# --- HTTP Listener (redirect to HTTPS) ---
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --- HTTPS Listener ---
# For production: add ACM certificate ARN
# Nokia AMF equivalent: N2 SCTP association termination with TLS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:ca-central-1:ACCOUNT_ID:certificate/CERT_ID" # Replace

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
