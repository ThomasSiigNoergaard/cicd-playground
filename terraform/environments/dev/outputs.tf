# These outputs are read by humans (terraform output) and by the deploy
# workflow, which uses alb_url for the GitHub environment URL and smoke test.

output "alb_url" {
  description = "Public URL of the dev environment."
  value       = module.app.alb_url
}

output "ecr_repository_url" {
  description = "ECR repository to push dev images to."
  value       = module.app.ecr_repository_url
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.app.cluster_name
}

output "service_name" {
  description = "ECS service name."
  value       = module.app.service_name
}

output "task_family" {
  description = "ECS task definition family."
  value       = module.app.task_family
}

output "container_name" {
  description = "Container name inside the task definition."
  value       = module.app.container_name
}

output "log_group_name" {
  description = "CloudWatch log group with the application logs."
  value       = module.app.log_group_name
}
