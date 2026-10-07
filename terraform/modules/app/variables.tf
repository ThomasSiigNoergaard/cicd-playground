variable "project_name" {
  description = "Short project name used as a prefix for every resource name."
  type        = string
  default     = "cicd-playground"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, digits or dashes and start with a letter."
  }
}

variable "environment" {
  description = "Environment name (dev, prod, ...). Part of every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or digits."
  }
}

variable "aws_region" {
  description = "Region the stack is deployed to. Used for the awslogs log driver configuration."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Each environment should use a distinct range so they could be peered later."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across. An ALB requires at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "use_private_subnets" {
  description = <<-EOT
    Where the Fargate tasks run.
      false (default, cheapest): tasks run in the public subnets with a public IP
        so they can pull images from ECR. The security group still only allows
        inbound traffic from the ALB, so they are not reachable from the internet.
      true: tasks run in private subnets and reach the internet through ONE NAT
        gateway (roughly 35+ USD per month plus data processing). A single NAT is
        a lab compromise; production would use one per AZ or VPC endpoints.
  EOT
  type        = bool
  default     = false
}

variable "container_image" {
  description = <<-EOT
    Image used by the task definition that Terraform creates. Leave null to use
    "<ecr repository url>:bootstrap". The deploy workflow registers new task
    definition revisions with real image digests, and Terraform ignores those
    changes (see lifecycle in ecs.tf), so this only matters on first creation.
  EOT
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB. Must be a valid combination with cpu."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. ARM64 (Graviton) is about 20% cheaper but the image must be built for linux/arm64."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the application log group."
  type        = number
  default     = 14
}

variable "ecr_untagged_expiry_days" {
  description = "Untagged images in ECR are deleted after this many days."
  type        = number
  default     = 7
}

variable "ecr_max_tagged_images" {
  description = "Maximum number of tagged images kept in ECR. Older ones are expired."
  type        = number
  default     = 30
}

variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete the ECR repository even if it still contains images. Handy for a lab, dangerous in production."
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the ECS cluster (small extra CloudWatch cost)."
  type        = bool
  default     = true
}

variable "alb_deletion_protection" {
  description = "Protect the load balancer from accidental deletion. Must be false before terraform destroy."
  type        = bool
  default     = false
}
