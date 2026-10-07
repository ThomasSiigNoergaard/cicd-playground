terraform {
  # Native S3 state locking (use_lockfile) needs Terraform 1.10 or newer.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.0" allows any 6.x release but never 7.0 (a major version can
      # contain breaking changes). The exact version that was tested is
      # recorded in each root module's .terraform.lock.hcl.
      version = "~> 6.0"
    }
  }
}
