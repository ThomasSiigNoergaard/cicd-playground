# -----------------------------------------------------------------------------
# Environment root: prod
#
# Each environment is its own Terraform root (own state file, own plan) that
# calls the shared module in ../../modules/app. The roots are deliberately
# tiny: only the backend, provider and the few values that differ per env.
# See docs/terraform.md for why this layout was chosen over workspaces or a
# single root with per-env tfvars.
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial backend configuration: the bucket name is account specific, so it
  # is supplied at init time instead of being hard coded:
  #
  #   terraform init -backend-config="bucket=<TF_STATE_BUCKET>"
  #
  # use_lockfile = true enables native S3 state locking (Terraform >= 1.10):
  # Terraform writes a .tflock object next to the state with a conditional
  # PUT, so no DynamoDB table is needed anymore.
  backend "s3" {
    key          = "env/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
