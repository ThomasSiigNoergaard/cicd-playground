# -----------------------------------------------------------------------------
# Application Load Balancer
#
# Internet -> ALB :80 -> target group (type ip) -> Fargate task :8080
#
# There is no custom domain in this lab, so the listener is plain HTTP on the
# generated ALB DNS name. With a domain you would add an ACM certificate, an
# HTTPS listener on 443 and redirect 80 -> 443 (see docs/terraform.md).
# -----------------------------------------------------------------------------

#trivy:ignore:AVD-AWS-0053 The ALB is intentionally internet facing; it is the public entry point of the API.
resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Reject requests with malformed headers instead of forwarding them. This
  # mitigates HTTP desync / request smuggling attacks.
  drop_invalid_header_fields = true

  enable_deletion_protection = var.alb_deletion_protection

  tags = { Name = local.name }
}

resource "aws_lb_target_group" "this" {
  # name_prefix (max 6 chars) instead of name lets create_before_destroy
  # replace the target group without a name collision.
  name_prefix = "app-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id

  # Fargate (awsvpc network mode) registers task ENI IPs, not instances.
  target_type = "ip"

  # How long the ALB keeps sending in-flight requests to a deregistering task.
  # The AWS default of 300s makes every deployment slow; 30s is plenty for an
  # API with short requests.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

#trivy:ignore:AVD-AWS-0054 No domain or certificate exists in this lab, so HTTPS is not possible. Add ACM + an HTTPS listener for real use.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
