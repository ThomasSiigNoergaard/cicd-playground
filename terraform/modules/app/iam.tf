# -----------------------------------------------------------------------------
# IAM roles for ECS
#
# ECS uses two different roles, which is a common source of confusion:
#
#   execution role: used by the ECS AGENT before your code starts, to pull the
#                   image from ECR and create log streams in CloudWatch.
#   task role:      assumed by YOUR APPLICATION at runtime (via the AWS SDK).
#                   This API calls no AWS services, so it has no permissions.
#
# Names must match "<project>-<env>-*" because the GitHub deploy role created
# in terraform/bootstrap can only manage roles with that prefix.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Confused deputy protection: only ECS tasks from THIS account can assume
    # the role, not ECS acting on behalf of some other account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution"
  description        = "ECS task execution role (image pull, log shipping) for ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# AWS managed policy granting ECR pull and CloudWatch Logs write access. It is
# the only managed policy the bootstrap deploy role is allowed to attach.
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_partition" "current" {}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  description        = "Runtime role for the ${local.name} application (intentionally no permissions)"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}
