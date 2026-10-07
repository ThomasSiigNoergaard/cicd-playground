variable "aws_region" {
  description = "AWS region for this environment. Must match the region the bootstrap roles are scoped to."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Project prefix for resource names. Must match the bootstrap stack, whose IAM permissions are scoped to it."
  type        = string
  default     = "cicd-playground"
}

variable "environment" {
  description = "Environment name. Fixed per root; exposed as a variable only so it can be referenced consistently."
  type        = string
  default     = "dev"
}
