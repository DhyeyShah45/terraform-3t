# output "bastion_public_ip" {
#   description = "The public IP of the bastion host to SSH into."
#   value       = aws_instance.bastion.public_ip
# }

output "vpc_id" {
  description = "The ID of the created VPC."
  value       = module.vpc.vpc_id
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository for pushing images."
  value       = aws_ecr_repository.app_repo.repository_url
}
