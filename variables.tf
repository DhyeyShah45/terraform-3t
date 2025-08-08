variable "aws_region" {
  type        = string
  description = "The AWS region where resources will be created."
  default     = "us-east-1"
#   sensitive = true # Hides the value when you write them in the terminal.
}

variable "vpc_cidr_block" {
  type        = string
  description = "The main CIDR block for the VPC."
  # No default, forces the user to provide a value.
}

variable "project_name" {
  description = "Name for the project."
  type        = string
}