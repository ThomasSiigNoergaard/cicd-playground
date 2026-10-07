provider "aws" {
  region = var.aws_region

  # Tags applied to every resource the module creates. Cost Explorer can then
  # group spend by Project and Environment.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "ThomasSiigNoergaard/cicd-playground"
    }
  }
}
