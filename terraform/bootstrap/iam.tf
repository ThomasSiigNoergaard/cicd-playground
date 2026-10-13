# -----------------------------------------------------------------------------
# IAM roles assumed by GitHub Actions through OIDC
#
# Trust is scoped with the token's `sub` (subject) claim, which GitHub builds
# from the workflow context:
#   - Job WITHOUT an environment on a pull_request event:
#       repo:OWNER/REPO:pull_request
#   - Job WITH `environment: dev` (any event):
#       repo:OWNER/REPO:environment:dev
#
# Mapping environments to roles is powerful because GitHub environments carry
# their own protection rules (required reviewers, deployment branch policies).
# The prod role can therefore only be assumed by a job that has already passed
# the prod approval gate and runs from an allowed branch. A pull request, even
# one that edits a workflow file, can never obtain prod credentials.
# -----------------------------------------------------------------------------

locals {
  oidc_sub_prefix = "repo:${var.github_repository}"

  state_bucket_arn = aws_s3_bucket.state.arn
}

# ---------------------------------------------------------------------------
# Plan role: used by `terraform plan` on pull requests.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    sid     = "GitHubActionsPullRequests"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # Always pin the audience. Without it, a token minted for another
    # relying party could in theory be replayed against AWS.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals (not StringLike with wildcards) so ONLY pull_request
    # tokens from this exact repository match.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project_name}-github-plan"
  description          = "Assumed by GitHub Actions pull_request jobs in ${var.github_repository} to run terraform plan."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# Trade-off: the AWS managed ReadOnlyAccess policy is broad (it can read most
# resource configuration in the account), but `terraform plan` needs to
# refresh every resource type the stacks manage and a hand written read list
# drifts every time the module grows. For a single-purpose lab account this is
# a sensible default. In a shared account, replace it with a narrower custom
# policy or use a dedicated account per environment.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# Plan needs to read state and to take (and release) the native S3 lock,
# which means writing and deleting ONLY the *.tflock objects. It can never
# overwrite a state file.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/env/*"]
  }

  statement {
    sid       = "ManageLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/env/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# ---------------------------------------------------------------------------
# Deploy roles: one per GitHub environment. Used by `terraform apply` and by
# the application deploy workflow (ECR push + ECS deploy).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy_trust" {
  for_each = var.environments

  statement {
    sid     = "GitHubActionsEnvironment${title(each.key)}"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_sub_prefix}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = var.environments

  name                 = "${var.project_name}-github-deploy-${each.key}"
  description          = "Assumed by GitHub Actions jobs running in the '${each.key}' environment of ${var.github_repository}."
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[each.key].json
  max_session_duration = 3600
}

# The deploy role must be able to CREATE the whole application stack, which is
# inherently powerful. Instead of AdministratorAccess it is limited to:
#   - the AWS services the app module actually uses,
#   - the configured region (aws:RequestedRegion),
#   - IAM roles whose names start with the project prefix, and PassRole only
#     to ECS tasks. This blocks the classic escalation path of creating an
#     admin role and assuming it.
# Remaining trade-off: within those services the role can touch resources that
# are not tagged for this project. Use one AWS account per environment (AWS
# Organizations) for real isolation; see docs/oidc.md.
data "aws_iam_policy_document" "deploy" {
  for_each = var.environments

  statement {
    sid = "AppServicesInRegion"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "ecs:*",
      "ecr:*",
      "logs:*",
      "cloudwatch:*",
      "application-autoscaling:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"]
  }

  # Attaching managed policies is limited to an allow-list, and creating inline
  # policies (iam:PutRolePolicy) is not granted at all. Without these limits
  # the role could give a project role AdministratorAccess and pass it to an
  # ECS task: a classic privilege escalation path. If the app later needs AWS
  # permissions, add a customer managed policy here in bootstrap (reviewed by
  # an admin) and append its ARN to this allow-list.
  statement {
    sid       = "AttachAllowListedManagedPolicies"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "PassProjectRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # ECS and ELB create their service-linked roles on first use in an account.
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }

  # Read-only IAM lookups the AWS provider performs while refreshing.
  statement {
    sid       = "ReadIamPolicies"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]
    resources = ["*"]
  }

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  # Each environment may only read and write its OWN state file, so a
  # compromised dev job cannot tamper with prod state.
  statement {
    sid       = "ReadWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/env/${each.key}/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = var.environments

  name   = "deploy-${each.key}"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}
