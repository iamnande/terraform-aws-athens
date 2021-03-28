# -----------------------------------------------------------------------------
# Deploy an Athens Proxy on AWS Fargate (ECS)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Require a minimum version of Terraform
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 0.13.0"
}

# -----------------------------------------------------------------------------
# Save the users from having to provide these values by looking them up.
# -----------------------------------------------------------------------------
data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

# -----------------------------------------------------------------------------
# Create a resource internal helpers.
# -----------------------------------------------------------------------------
locals {
  name   = "athens-proxy"
  prefix = var.prefix != "" ? "${var.prefix}-" : var.prefix
}

# -----------------------------------------------------------------------------
# Create the storage backend bucket.
#
# without prefix: athens-proxy-us-east-1-123456789012
# with prefix: company-athens-proxy-us-east-1-123456789012
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket = "${local.prefix}${local.name}-${data.aws_region.this.name}-${data.aws_caller_identity.this.account_id}"
}

# -----------------------------------------------------------------------------
# Create the IAM task & execution roles.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name               = "${local.prefix}${local.name}-execution-${data.aws_region.this.name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "execution" {
  name   = "${local.prefix}${local.name}-execution-${data.aws_region.this.name}"
  policy = data.aws_iam_policy_document.execution_policy.json
  path   = "/"
}

data "aws_iam_policy_document" "execution_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_attachment" {
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution.arn
}

resource "aws_iam_role" "task" {
  name               = "${local.prefix}${local.name}-task-${data.aws_region.this.name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "execution" {
  name   = "${local.prefix}${local.name}-task-${data.aws_region.this.name}"
  policy = data.aws_iam_policy_document.task_policy.json
  path   = "/"
}

data "aws_iam_policy_document" "task_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.this.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    resources = ["*"]
  }
}

# -----------------------------------------------------------------------------
# Create ingress/egress rules for traffic flow.
#
# These rules allow normal HTTP traffic into the load balancer only. In addition,
# the load balancer can communicate with the ECS tasks. Finally, the ECS tasks
# have open egress to fetch from the various upstream sources.
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.prefix}${local.name}-alb"
  description = "ALB Ingress"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.prefix}${local.name}-ecs"
  description = "ALB to ECS Ingress"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # note: This is important to include because we're referencing another security
  # group. If it were not included, updates/deletes would likely hang or trip on
  # race conditions.
  revoke_rules_on_delete = true
}

# -----------------------------------------------------------------------------
# Create certificate to attach to the load balancer.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
  domain_name       = "${var.dns_record_name}.${var.dns_domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Create the load balancer and secure-by-default listeners.
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  name                       = "${local.prefix}${local.name}-alb"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.lb_subnets
  security_groups            = [aws_security_group.alb.id]
  enable_deletion_protection = false
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.this.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
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

resource "aws_lb_target_group" "this" {
  name        = "${local.prefix}${local.name}-targets"
  protocol    = "HTTP"
  port        = 3000
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path    = "/"
    matcher = "200"
  }
}

# -----------------------------------------------------------------------------
# Create the route53 record for the service.
# -----------------------------------------------------------------------------
resource "aws_route53_record" "this" {
  zone_id        = var.dns_zone_id
  name           = "${var.dns_record_name}.${var.dns_domain_name}"
  set_identifier = "${var.dns_record_name}-${data.aws_region.this.name}"
  type           = "A"

  latency_routing_policy {
    region = data.aws_region.this.name
  }

  alias {
    zone_id                = aws_lb.this.zone_id
    name                   = aws_lb.this.dns_name
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Create the log group for capturing container logs.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "${local.prefix}${local.name}"
  retention_in_days = 3
}

# -----------------------------------------------------------------------------
# Create the ECS cluster and service.
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.prefix}${local.name}"
}

resource "aws_ecs_service" "this" {
  name            = "${local.prefix}${local.name}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  desired_count   = 3

  platform_version = "1.4.0"

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "${local.prefix}${local.name}"
    container_port   = 3000
  }

  network_configuration {
    security_groups = [aws_security_group.ecs.id]
    subnets         = var.container_subnets
  }
}

resource "aws_ecs_task_definition" "this" {
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  family                   = "${local.prefix}${local.name}"
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions    = data.template_file.this.rendered
  cpu                      = 1024
  memory                   = 2048
}

data "template_file" "this" {
  template = file("${path.module}/files/task.json.tpl")

  vars = {
    container   = var.container
    s3_bucket   = aws_s3_bucket.this.id
    aws_region  = data.aws_region.this.name
    service     = "${local.prefix}${local.name}"
    log_group   = aws_cloudwatch_log_group.this.name
    gonosum     = var.athens_gonosum_patterns
    go_env_vars = var.athens_go_binary_envvars
  }
}