# -----------------------------------------------------------------------------
# CloudWatch log group for the application container.
#
# The API writes structured JSON to stdout; the awslogs driver ships it here,
# where CloudWatch Logs Insights can query fields like LogLevel directly.
# -----------------------------------------------------------------------------

#trivy:ignore:AVD-AWS-0017 -- Lab trade-off: CloudWatch Logs already encrypts at rest with an AWS owned key; a customer managed KMS key costs ~1 USD/month and needs key policy plumbing.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
}
