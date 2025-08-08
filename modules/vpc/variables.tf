variable "project_name" {
  description = "Name of the project to use as a prefix."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "A list of availability zones for the subnets."
  type        = list(string)
}