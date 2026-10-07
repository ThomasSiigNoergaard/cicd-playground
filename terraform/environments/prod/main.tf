module "app" {
  source = "../../modules/app"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # prod: distinct CIDR (so dev and prod could be peered later) and longer log
  # retention plus Container Insights for better observability.
  #
  # Cost-conscious lab default: prod ALSO runs tasks in public subnets without
  # a NAT gateway. For a real production workload set use_private_subnets =
  # true, which creates a single NAT gateway and moves tasks off the internet
  # (see docs/terraform.md for the cost/availability trade-off).
  vpc_cidr            = "10.20.0.0/16"
  use_private_subnets = false

  log_retention_days        = 30
  enable_container_insights = true
}
