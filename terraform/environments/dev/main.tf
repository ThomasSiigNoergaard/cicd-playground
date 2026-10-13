module "app" {
  source = "../../modules/app"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # dev: cheapest possible setup. Tasks run in public subnets with a public IP
  # (still only reachable through the ALB thanks to the security groups), so
  # no NAT gateway (~35 USD/month) is needed.
  vpc_cidr            = "10.10.0.0/16"
  use_private_subnets = false

  log_retention_days        = 7
  enable_container_insights = false
}
