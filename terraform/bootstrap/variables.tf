variable "aws_region" {
  description = "AWS region for the state bucket and the default region used by the environment stacks."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short project identifier used as a prefix for resource names and in tags."
  type        = string
  default     = "cicd-playground"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "The project_name must be 3-32 characters of lowercase letters, digits and dashes."
  }
}

variable "github_repository" {
  description = "GitHub repository in OWNER/REPO form that is allowed to assume the roles via OIDC."
  type        = string
  default     = "ThomasSiigNoergaard/cicd-playground"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "The github_repository must be in OWNER/REPO form."
  }
}

variable "environments" {
  description = "GitHub environment names that get their own deploy role. Must match the environment roots under terraform/environments/."
  type        = set(string)
  default     = ["dev", "prod"]
}

variable "create_oidc_provider" {
  description = <<-EOT
    Whether to create the IAM OIDC provider for token.actions.githubusercontent.com.
    An AWS account can only hold ONE provider per URL, so set this to false if the
    account already has it (for example from another project) and it will be looked up instead.
  EOT
  type        = bool
  default     = true
}
