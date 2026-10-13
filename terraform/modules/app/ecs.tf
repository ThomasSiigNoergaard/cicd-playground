# -----------------------------------------------------------------------------
# ECS cluster, task definition and Fargate service
#
# Ownership split between Terraform and the deploy workflow:
#   - Terraform owns the infrastructure: cluster, service, networking and an
#     INITIAL task definition (revision 1).
#   - .github/workflows/deploy.yml owns application releases: it downloads the
#     current task definition, swaps in the new image and registers a new
#     revision, then updates the service.
# To stop the two fighting, the service ignores changes to task_definition
# and desired_count (see lifecycle below). This is the standard pattern when
# CI deploys and Terraform provisions.
# -----------------------------------------------------------------------------

locals {
  container_name = "api"

  # Before the first deploy the ECR repo is empty. The service starts with
  # desired_count = 0, so this placeholder image is never actually pulled.
  container_image = coalesce(var.container_image, "${aws_ecr_repository.this.repository_url}:bootstrap")

  task_subnet_ids = var.use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  # Container Insights adds per-task CPU/memory/network metrics. It costs a
  # little extra (custom metrics); toggle it off with the variable if needed.
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # mandatory for Fargate: each task gets its own ENI
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ASPNETCORE_HTTP_PORTS", value = tostring(var.container_port) },
        { name = "DEPLOY_ENVIRONMENT", value = var.environment },
      ]

      # Defence in depth: the app never writes to disk, so make the root
      # filesystem read-only (verified locally with `docker run --read-only`).
      readonlyRootFilesystem = true

      # The chiseled image has no shell or curl, so the health check reuses
      # the app binary itself (see HealthProbe.cs and the Dockerfile).
      healthCheck = {
        command     = ["CMD", "dotnet", "CicdPlayground.Api.dll", "--health-probe"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = local.container_name
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"

  # Zero until the first real image exists. deploy.yml scales it to 1.
  desired_count = 0

  # Rolling deployment that keeps capacity: start new tasks before stopping
  # old ones. The circuit breaker rolls back automatically if new tasks keep
  # failing their health checks, so a bad image cannot take the service down.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Give the app time to boot before ALB health checks can fail the task.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = local.task_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = !var.use_private_subnets # needed to reach ECR without NAT
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # Copy the service tags onto each task so task costs carry the same tags.
  propagate_tags = "SERVICE"

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  # The target group must be attached to a listener before a service can
  # register targets in it.
  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.execution]
}
