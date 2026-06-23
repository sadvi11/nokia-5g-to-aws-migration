# =============================================================================
# Module 03: ECS Fargate — Nokia CBAM (Cloud Band Application Manager) Equivalent
# =============================================================================
#
# Nokia CBAM: ETSI NFV-compliant VNFM that automates CNF lifecycle:
#   - Onboarding CNF packages (Helm charts) into catalog
#   - Instantiation onto Kubernetes namespaces with resource quotas
#   - Scaling: HPA for SMF based on session rate; vertical for UPF
#   - Healing: detects pod crashes via liveness probes, re-instantiates
#   - Rolling upgrades: zero-downtime via K8s rolling deployment strategy
#   Source: Nokia CBAM datasheet (nokia.com/asset/f/200057/)
#   "CBAM automates lifecycle management by providing an open templating
#    system, managing resources and applying associated workflows."
#
# AWS Mapping:
#   CBAM Helm chart catalog     → ECS task definitions
#   CBAM instantiation          → ECS run-task / create-service
#   CBAM HPA scaling            → ECS Application Auto Scaling
#   CBAM healing (liveness)     → ECS health checks + service scheduler
#   CBAM rolling upgrades       → ECS rolling deployment (maxUnavailable: 0)
#   CBAM resource quotas        → ECS task CPU/memory limits
#   CBAM multi-VIM support      → ECS Fargate (no server management)
# =============================================================================

# --- ECS Cluster (Nokia CBAM-managed Kubernetes cluster equivalent) ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-cluster"
    NokiaMapping = "CBAM-ManagedCluster"
    Description  = "Container cluster - maps to Nokia CBAM-managed K8s cluster"
  }
}

# --- ECS Task Execution Role (CBAM service account equivalent) ---
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-${var.environment}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    NokiaMapping = "CBAM-ServiceAccount"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Role (CNF instance IAM — least privilege) ---
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    NokiaMapping = "CNF-InstanceRole"
    Description  = "Least privilege for tasks - maps to Nokia CNF K8s RBAC"
  }
}

# Task role policy: access DynamoDB + Kinesis (UDM + OAM bus)
resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-*"
      },
      {
        Sid    = "KinesisAccess"
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = "arn:aws:kinesis:*:*:stream/${var.project_name}-*"
      }
    ]
  })
}

# --- Security Group for ECS Tasks (CNF pod network policy equivalent) ---
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-${var.environment}-ecs-"
  description = "ECS task SG - Nokia CNF pod network policy equivalent"
  vpc_id      = var.vpc_id

  # Inbound: only from ALB (AMF → SMF internal signaling)
  ingress {
    description     = "Traffic from ALB only - maps to Nokia SBI internal traffic"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  # Outbound: to AWS services (DynamoDB, Kinesis, ECR)
  egress {
    description = "Outbound to AWS services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-ecs-sg"
    NokiaMapping = "CNF-PodNetworkPolicy"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- CloudWatch Log Group for ECS ---
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    NokiaMapping = "CNF-ApplicationLogs"
  }
}

# --- ECS Task Definition (Nokia CBAM Helm chart equivalent) ---
# CBAM onboards CNF packages as Helm charts with resource definitions.
# ECS task definitions serve the same purpose: container image, CPU, memory, ports.
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-app"
      image = var.container_image
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Health check = Nokia CBAM liveness probe
      # CBAM detects pod crashes via K8s liveness probes and auto-heals
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      # Resource limits = Nokia CBAM resource quotas per CNF instance
      # CBAM enforces CPU/memory limits per CNF — prevents noisy neighbour
      # Same pattern: Fargate enforces hard limits per task

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = "ca-central-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "PROJECT",     value = var.project_name }
      ]
    }
  ])

  tags = {
    NokiaMapping = "CBAM-HelmChart"
    Description  = "Task definition - maps to Nokia CBAM CNF package (Helm chart)"
  }
}

# --- ECS Service (Nokia CBAM CNF instance pool equivalent) ---
# CBAM maintains a pool of CNF instances with desired count, scaling, healing.
# ECS Service does the same: desired count + deployment config + auto-healing.
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Rolling deployment = Nokia CBAM zero-downtime CNF upgrade
  # CBAM coordinates rolling upgrades across interdependent NFs.
  # maxUnavailable: 0 = no task killed until replacement passes health check
  deployment_configuration {
    maximum_percent         = 200  # Allow 2x during deployment (surge)
    minimum_healthy_percent = 100  # Never go below desired count
  }

  # Spread across AZs = Nokia cloud zone distribution
  # Nokia runs CNF pools across 3+ cloud zones for N+1 redundancy
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # CNFs run on private network (SBI)
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "${var.project_name}-app"
    container_port   = var.container_port
  }

  # Service discovery registration (NRF equivalent)
  service_registries {
    registry_arn = aws_service_discovery_service.main.arn
  }

  # Force new deployment on task definition change
  force_new_deployment = true

  tags = {
    NokiaMapping = "CBAM-CNFPool"
    Description  = "Service pool - maps to Nokia CBAM managed CNF instance pool"
  }

  depends_on = [var.alb_target_group_arn]
}

# --- Service Discovery Registration (NRF registration equivalent) ---
resource "aws_service_discovery_service" "main" {
  name = "${var.project_name}-${var.environment}"

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    NokiaMapping = "NRF-NFRegistration"
    Description  = "Service registers here - maps to Nokia NRF Nnrf_NFManagement"
  }
}

# --- Auto Scaling (Nokia CBAM HPA equivalent) ---
# CBAM uses Kubernetes HPA to scale SMF based on PDU session rate.
# ECS Application Auto Scaling does the same based on CPU/request count.
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on CPU (Nokia: scale SMF on PDU session processing load)
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Scale on request count (Nokia: scale AMF on registration rate)
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.project_name}-${var.environment}-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_ecs_service.main.name}/${var.alb_target_group_arn}"
    }
    target_value       = 1000.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
