output "aws_region" {
  description = "Region to store in the AWS_REGION repository variable."
  value       = var.aws_region
}

output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Store it in the TF_STATE_BUCKET repository variable."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Role assumed by pull_request jobs for terraform plan. Store it in the AWS_PLAN_ROLE_ARN repository variable."
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arns" {
  description = "Map of GitHub environment name to deploy role ARN. Store each in the AWS_DEPLOY_ROLE_ARN variable of the matching environment."
  value       = { for env, role in aws_iam_role.deploy : env => role.arn }
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = local.github_oidc_provider_arn
}

output "gh_variable_commands" {
  description = "Copy-paste commands that configure the GitHub repository and environment variables from these outputs."
  value = join("\n", concat(
    [
      "gh variable set AWS_REGION --repo ${var.github_repository} --body '${var.aws_region}'",
      "gh variable set TF_STATE_BUCKET --repo ${var.github_repository} --body '${aws_s3_bucket.state.bucket}'",
      "gh variable set AWS_PLAN_ROLE_ARN --repo ${var.github_repository} --body '${aws_iam_role.plan.arn}'",
    ],
    [for env, role in aws_iam_role.deploy : "gh variable set AWS_DEPLOY_ROLE_ARN --repo ${var.github_repository} --env ${env} --body '${role.arn}'"],
  ))
}
