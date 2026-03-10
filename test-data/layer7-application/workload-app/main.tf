# layer7-application/workload-app/main.tf
# Layer 7 — Application Layer: workload-app (ECS Fargate + Lambda + API Gateway)
# Detection signals: application-*, workload-*, app*.tf, custom-*.tf

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "applications/workload-app/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-production"
    kms_key_id     = "alias/enterprise-tfstate-key"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      "enterprise-app-id" = var.app_id
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = var.cost_center
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS key for application resources ─────────────────────────────────────────

resource "aws_kms_key" "app" {
  description             = "KMS CMK for workload-app ${var.app_name} — ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
  }
}

resource "aws_kms_alias" "app" {
  name          = "alias/enterprise-app-${var.app_name}"
  target_key_id = aws_kms_key.app.key_id
}

# ── ECR Repository ────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "enterprise/${var.app_name}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.app.arn
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 production images"
        selection = {
          tagStatus      = "tagged"
          tagPrefixList  = ["prod-", "release-"]
          countType      = "imageCountMoreThan"
          countNumber    = 30
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "app" {
  name = "enterprise-${var.app_name}-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.app.arn
      logging    = "OVERRIDE"
      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "compute"           = "ecs"
    "fargate"           = "true"
    "container"         = "true"
  }
}

resource "aws_ecs_cluster_capacity_providers" "app" {
  cluster_name       = aws_ecs_cluster.app.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ── ECS Task Definition ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "app" {
  family                   = "enterprise-${var.app_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # Ephemeral storage encryption
  ephemeral_storage {
    size_in_gib = 50
  }

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.container_image_tag}"
      essential = true
      cpu       = var.task_cpu
      memory    = var.task_memory

      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
        name          = "http"
        appProtocol   = "http"
      }]

      environment = [
        { name = "APP_ENV",        value = var.environment },
        { name = "APP_NAME",       value = var.app_name },
        { name = "AWS_REGION",     value = var.aws_region },
        { name = "OTEL_EXPORTER",  value = "XRAY" },
      ]

      secrets = [
        { name = "DB_SECRET_ARN",    valueFrom = var.db_secret_arn },
        { name = "REDIS_AUTH_TOKEN", valueFrom = var.redis_secret_arn },
        { name = "API_KEY",          valueFrom = "${var.app_secret_arn}:api_key::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "false"
          "mode"                  = "non-blocking"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      readonlyRootFilesystem = true
      user                   = "1000:1000"  # Non-root user

      ulimits = [{
        name      = "nofile"
        softLimit = 65536
        hardLimit = 65536
      }]
    },
    {
      # OTEL / X-Ray sidecar
      name      = "aws-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = false
      cpu       = 128
      memory    = 256
      command   = ["--config=/etc/ecs/ecs-default-config.yaml"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "otel"
        }
      }
    }
  ])

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "compute"           = "fargate"
    "docker"            = "container"
  }
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name                               = "enterprise-${var.app_name}"
  cluster                            = aws_ecs_cluster.app.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  health_check_grace_period_seconds  = 120
  enable_execute_command             = false  # Disabled in prod (SOX)
  propagate_tags                     = "TASK_DEFINITION"

  deployment_configuration {
    minimum_healthy_percent = 100
    maximum_percent         = 200
    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.app.arn
    service {
      port_name = "http"
      client_alias {
        port     = 8080
        dns_name = var.app_name
      }
    }
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "compute"           = "ecs-service"
  }
}

# ── ALB + Target Group ────────────────────────────────────────────────────────

resource "aws_lb" "app" {
  name               = "enterprise-${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = true
  enable_http2               = true
  idle_timeout               = 60

  access_logs {
    bucket  = var.alb_logs_bucket
    prefix  = "alb/${var.app_name}"
    enabled = true
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
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

resource "aws_lb_target_group" "app" {
  name        = "enterprise-${var.app_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# ── Lambda Function (async data processor) ────────────────────────────────────

resource "aws_lambda_function" "processor" {
  function_name = "enterprise-${var.app_name}-processor"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:processor-${var.container_image_tag}"
  role          = aws_iam_role.lambda.arn
  timeout       = 300
  memory_size   = 1024
  architectures = ["arm64"]

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      APP_ENV               = var.environment
      APP_NAME              = var.app_name
      AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
      DB_SECRET_ARN         = var.db_secret_arn
      REDIS_SECRET_ARN      = var.redis_secret_arn
      MSK_BOOTSTRAP_SERVERS = var.msk_bootstrap_brokers
      OPENSEARCH_ENDPOINT   = var.opensearch_endpoint
      KMS_KEY_ARN           = aws_kms_key.app.arn
      OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4316"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tracing_config {
    mode = "Active"
  }

  ephemeral_storage {
    size = 1024
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  image_config {
    entry_point = ["/lambda-entrypoint.sh"]
    command     = ["handler.process"]
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "compute"           = "lambda"
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = aws_sqs_queue.events.arn
  function_name                      = aws_lambda_function.processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 30
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 100
  }
}

# ── SQS Queues ────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "events" {
  name                              = "enterprise-${var.app_name}-events"
  delay_seconds                     = 0
  max_message_size                  = 262144
  message_retention_seconds         = 86400
  receive_wait_time_seconds         = 20
  visibility_timeout_seconds        = 330  # > Lambda timeout
  kms_master_key_id                 = aws_kms_key.app.id
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.lambda_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "messaging"         = "sqs"
    "queue"             = "events"
  }
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "enterprise-${var.app_name}-dlq"
  message_retention_seconds = 1209600  # 14 days
  kms_master_key_id         = aws_kms_key.app.id

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "queue"             = "dlq"
  }
}

# ── CloudFront Distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = "PriceClass_100"
  default_root_object = "index.html"
  comment             = "enterprise-${var.app_name} CDN distribution"

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "ALB-${var.app_name}"
    origin_path = ""

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.cloudfront_origin_secret
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${var.app_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host", "Origin", "Referer"]
      cookies {
        forward = "all"
      }
    }
  }

  web_acl_id = var.cloudfront_waf_arn

  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_geo_restriction_type
      locations        = var.cloudfront_geo_restriction_locations
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
    bucket          = "${var.alb_logs_bucket}.s3.amazonaws.com"
    prefix          = "cloudfront/${var.app_name}/"
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "cdn"               = "cloudfront"
    "edge"              = "true"
  }
}

# ── Auto Scaling ──────────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.app.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "enterprise-${var.app_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "enterprise-${var.app_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# ── IAM Roles ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_execution" {
  name                 = "enterprise-${var.app_name}-ecs-execution"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "role-type"         = "ecs-execution"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "secrets-and-kms"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "kms:Decrypt"]
        Resource = [var.db_secret_arn, var.redis_secret_arn, var.app_secret_arn, aws_kms_key.app.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name                 = "enterprise-${var.app_name}-ecs-task"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "role-type"         = "ecs-task"
  }
}

resource "aws_iam_role" "lambda" {
  name                 = "enterprise-${var.app_name}-lambda"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "workload-app"      = var.app_name
    "role-type"         = "lambda"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ── Service Discovery ────────────────────────────────────────────────────────

resource "aws_service_discovery_private_dns_namespace" "app" {
  name        = "${var.app_name}.${var.environment}.internal"
  description = "Service discovery namespace for workload-app ${var.app_name}"
  vpc         = var.vpc_id
}

# ── CloudWatch Monitoring ────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/enterprise/ecs/${var.app_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.app.arn
  tags = { "enterprise-app-id" = var.app_id, "environment" = var.environment, "managed-by" = "terraform", "cost-center" = var.cost_center }
}

resource "aws_cloudwatch_log_group" "otel" {
  name              = "/enterprise/ecs/${var.app_name}/otel"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.app.arn
  tags = { "enterprise-app-id" = var.app_id, "environment" = var.environment, "managed-by" = "terraform", "cost-center" = var.cost_center }
}

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/enterprise/ecs/${var.app_name}/exec"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.app.arn
  tags = { "enterprise-app-id" = var.app_id, "environment" = var.environment, "managed-by" = "terraform", "cost-center" = var.cost_center }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "enterprise-${var.app_name}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "workload-app: ALB 5XX error rate > 10/min for ${var.app_name}"
  alarm_actions       = [var.sns_alert_arn]
  dimensions = { LoadBalancer = aws_lb.app.arn_suffix, TargetGroup = aws_lb_target_group.app.arn_suffix }
  tags = { "enterprise-app-id" = var.app_id, "environment" = var.environment, "managed-by" = "terraform", "cost-center" = var.cost_center }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "enterprise-${var.app_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "workload-app: ECS CPU > 80% for ${var.app_name}"
  alarm_actions       = [var.sns_alert_arn]
  dimensions = { ClusterName = aws_ecs_cluster.app.name, ServiceName = aws_ecs_service.app.name }
}

# ── Secrets for application ───────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "app" {
  name        = "enterprise/${var.app_id}/${var.app_name}/app-secrets"
  description = "workload-app: Application secrets for ${var.app_name}"
  kms_key_id  = aws_kms_key.app.arn
  recovery_window_in_days = 30
  tags = { "enterprise-app-id" = var.app_id, "environment" = var.environment, "managed-by" = "terraform", "cost-center" = var.cost_center }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "alb_dns_name"           { value = aws_lb.app.dns_name }
output "cloudfront_domain"      { value = aws_cloudfront_distribution.app.domain_name }
output "ecs_cluster_arn"        { value = aws_ecs_cluster.app.arn }
output "ecs_service_name"       { value = aws_ecs_service.app.name }
output "ecr_repository_url"     { value = aws_ecr_repository.app.repository_url }
output "lambda_function_arn"    { value = aws_lambda_function.processor.arn }
output "events_queue_url"       { value = aws_sqs_queue.events.url }
output "dlq_url"                { value = aws_sqs_queue.lambda_dlq.url }

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"                        { type = string; default = "us-east-1" }
variable "environment"                       { type = string; default = "production" }
variable "app_id"                            { type = string }
variable "app_name"                          { type = string }
variable "cost_center"                       { type = string; default = "CC-APP-007" }
variable "container_image_tag"               { type = string; default = "latest" }
variable "task_cpu"                          { type = number; default = 1024 }
variable "task_memory"                       { type = number; default = 2048 }
variable "desired_count"                     { type = number; default = 2 }
variable "min_count"                         { type = number; default = 2 }
variable "max_count"                         { type = number; default = 20 }
variable "lambda_reserved_concurrency"       { type = number; default = 50 }
variable "vpc_id"                            { type = string }
variable "private_subnet_ids"               { type = list(string) }
variable "public_subnet_ids"                { type = list(string) }
variable "app_security_group_id"             { type = string }
variable "alb_security_group_id"             { type = string }
variable "lambda_security_group_id"          { type = string }
variable "alb_logs_bucket"                   { type = string }
variable "acm_certificate_arn"              { type = string }
variable "cloudfront_certificate_arn"       { type = string }
variable "cloudfront_waf_arn"               { type = string; default = "" }
variable "cloudfront_origin_secret"         { type = string; sensitive = true }
variable "cloudfront_geo_restriction_type"  { type = string; default = "none" }
variable "cloudfront_geo_restriction_locations" { type = list(string); default = [] }
variable "waf_web_acl_arn"                  { type = string }
variable "db_secret_arn"                    { type = string }
variable "redis_secret_arn"                 { type = string }
variable "app_secret_arn"                   { type = string; default = "" }
variable "msk_bootstrap_brokers"            { type = string; default = "" }
variable "opensearch_endpoint"              { type = string; default = "" }
variable "sns_alert_arn"                    { type = string }
variable "permissions_boundary_arn"         { type = string }
