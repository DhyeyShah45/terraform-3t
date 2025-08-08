output "bastion_public_ip" {
  description = "The public IP of the bastion host to SSH into."
  value       = aws_instance.bastion.public_ip
}

output "vpc_id" {
  description = "The ID of the created VPC."
  value       = module.vpc.vpc_id
}