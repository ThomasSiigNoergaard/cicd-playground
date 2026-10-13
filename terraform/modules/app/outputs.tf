output "alb_url" {
  description = "Public URL of the application load balancer."
  value       = "http://${aws_lb.this.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL (registry/repo) to push images to."
  value       = aws_ecr_repository.this.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "task_family" {
  description = "ECS task definition family used by the deploy workflow."
  value       = aws_ecs_task_definition.app.family
}

output "container_name" {
  description = "Name of the application container in the task definition."
  value       = local.container_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "log_group_name" {
  description = "CloudWatch log group for the application."
  value       = aws_cloudwatch_log_group.app.name
}
