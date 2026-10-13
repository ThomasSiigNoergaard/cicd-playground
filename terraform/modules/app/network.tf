# -----------------------------------------------------------------------------
# Networking
#
#   VPC (vpc_cidr)
#   +-- public subnets  (one per AZ): ALB, plus the Fargate tasks by default
#   +-- private subnets (one per AZ): Fargate tasks when use_private_subnets
#   +-- Internet gateway for the public subnets
#   +-- Optional single NAT gateway for the private subnets
#
# Private subnets are always created (they are free) so switching
# use_private_subnets on later does not renumber anything.
# -----------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # cidrsubnet(prefix, newbits, netnum): with a /16 VPC and 8 new bits every
  # subnet is a /24. Public subnets use netnum 0..n, private 100..n.
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}

data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones and Wavelength Zones, which do not support every service.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

#trivy:ignore:AVD-AWS-0178 VPC Flow Logs are off to keep the lab cheap. Enable them (to CloudWatch or S3) for anything real.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

# The default security group of a VPC allows all traffic between its members.
# Adopting it with no rules strips that, so nothing can rely on it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-default-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = local.name }
}

#trivy:ignore:AVD-AWS-0164 Public subnets intentionally auto-assign public IPs. They host the internet facing ALB and (in the cheap default) the Fargate tasks, which are still only reachable from the ALB security group.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name}-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Optional NAT gateway (only when tasks run in private subnets)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = var.use_private_subnets ? 1 : 0

  domain = "vpc"

  tags = { Name = "${local.name}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.use_private_subnets ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = local.name }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.use_private_subnets ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = { Name = "${local.name}-private" }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Security groups
#
# Rules are separate resources (aws_vpc_security_group_*_rule) instead of
# inline blocks. That is the current AWS provider recommendation: every rule
# gets its own ID and description, and you avoid the inline-vs-separate
# conflicts that cause perpetual diffs.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Internet facing ALB for ${local.name}"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-alb" }
}

#trivy:ignore:AVD-AWS-0107 A public web endpoint must accept traffic from the internet.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# The ALB only needs to talk to the tasks, so egress is limited to the task
# security group on the container port.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To Fargate tasks"
  referenced_security_group_id = aws_security_group.tasks.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "tasks" {
  name        = "${local.name}-tasks"
  description = "Fargate tasks for ${local.name}"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-tasks" }
}

# Only the ALB may reach the containers. Even with a public IP the tasks are
# not reachable directly from the internet.
resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "From the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Tasks need outbound HTTPS to pull images from ECR and ship logs to
# CloudWatch. With VPC endpoints (ecr.api, ecr.dkr, s3, logs) this could be
# restricted further, at roughly 7 USD per endpoint per AZ per month.
#trivy:ignore:AVD-AWS-0104 Outbound HTTPS is required to reach ECR and CloudWatch Logs without paid VPC endpoints.
resource "aws_vpc_security_group_egress_rule" "tasks_https" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to AWS APIs (ECR, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
