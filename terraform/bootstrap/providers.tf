provider "aws" {
  region = var.aws_region

  # default_tags are merged into every taggable resource this provider creates,
  # which is far less error prone than remembering a tags block on each one.
  default_tags {
    tags = {
      Project   = var.project_name
      Stack     = "bootstrap"
      ManagedBy = "terraform"
      Repo      = var.github_repository
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
