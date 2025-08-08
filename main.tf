provider "aws" {
  region  = var.aws_region
  profile = "terraform"
}

# Call our reusable VPC module
module "vpc" {
  source             = "./modules/vpc" # Path to the module
  project_name       = var.project_name
  vpc_cidr_block     = var.vpc_cidr_block
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}

# Create a Security Group for the Bastion Host
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH and HTTP traffic to bastion"
  vpc_id      = module.vpc.vpc_id

  # Allow SSH from anywhere (for easy access in this demo)
  # In production, you would restrict this to your IP: cidr_blocks = ["YOUR_IP/32"]
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Bastion Host in a Public Subnet
# Its purpose is to be the secure entry point to access instances in private subnets.
resource "aws_instance" "bastion" {
  # A standard, free-tier eligible AMI for Amazon Linux 2
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  # Place it in the FIRST public subnet created by our module
  subnet_id = module.vpc.public_subnet_ids[0]

  # Attach the security group
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  # You need a key pair to SSH into the instance
  # key_name = "your-aws-key-pair-name" 

  tags = {
    Name = "${var.project_name}-bastion-host"
  }
}
