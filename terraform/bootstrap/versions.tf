# -----------------------------------------------------------------------------
# Bootstrap stack - version constraints
#
# This stack is the "chicken and egg" breaker: it creates the S3 bucket that
# every other stack stores its state in, plus the IAM OIDC trust that lets
# GitHub Actions talk to AWS without long-lived keys. Because the state bucket
# does not exist yet when this stack first runs, the bootstrap stack itself
# uses LOCAL state (terraform.tfstate next to these files). See README.md in
# this folder for how to optionally migrate it into the bucket afterwards.
# -----------------------------------------------------------------------------
terraform {
  # 1.10 introduced native S3 state locking (use_lockfile = true), which the
  # environment stacks rely on instead of a DynamoDB lock table.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pessimistic constraint: allow 6.x minor/patch updates, never 7.0.
      # The exact version actually used is recorded in .terraform.lock.hcl,
      # which is committed so every machine and CI run uses identical builds.
      version = "~> 6.0"
    }
  }
}
