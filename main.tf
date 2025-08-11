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

# --- 2. IAM Roles ---
# Role for the EC2 instances to register with the ECS cluster
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# --- 3. ECR Repository ---
resource "aws_ecr_repository" "app_repo" {
  name = "${var.project_name}/app"
}

# --- 4. ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# --- 5. Security Group for ECS Instances ---
resource "aws_security_group" "ecs_instance_sg" {
  name        = "${var.project_name}-ecs-instance-sg"
  description = "Allow traffic for ECS instances"
  vpc_id      = module.vpc.vpc_id

  # In a real app, you'd restrict ingress to the Load Balancer's security group.
  # For now, we allow all internal traffic.
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow all outbound traffic so instances can pull images from ECR via NAT Gateway
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 6. Launch Template & Auto Scaling Group ---
# Find the latest ECS-Optimized Amazon Linux 2 AMI
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "ecs_launch_template" {
  name          = "${var.project_name}-launch-template"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t2.micro" # Free Tier eligible

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_instance_sg.id]

  # This script registers the instance with our specific ECS cluster
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${var.project_name}-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = module.vpc.private_subnet_ids # IMPORTANT: We use private subnets

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  # This tag allows ECS to manage scaling actions on the ASG
  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-instance"
    propagate_at_launch = true
  }
}

# --- 7. Link ASG to ECS Cluster & Enable Managed Scaling ---
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "${var.project_name}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 80 # Aim to keep overall resource utilization at 80%
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_attachment" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  }
}


# # Create a Security Group for the Bastion Host
# resource "aws_security_group" "bastion_sg" {
#   name        = "${var.project_name}-bastion-sg"
#   description = "Allow SSH and HTTP traffic to bastion"
#   vpc_id      = module.vpc.vpc_id

#   # Allow SSH from anywhere (for easy access in this demo)
#   # In production, you would restrict this to your IP: cidr_blocks = ["YOUR_IP/32"]
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # Allow HTTP (port 80)
#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # Allow all outbound traffic
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # Create a Bastion Host in a Public Subnet
# # Its purpose is to be the secure entry point to access instances in private subnets.
# resource "aws_instance" "bastion" {
#   # A standard, free-tier eligible AMI for Ubuntu Linux
#   ami           = "ami-020cba7c55df1f615"
#   instance_type = "t2.micro"

#   # Place it in the FIRST public subnet created by our module
#   subnet_id = module.vpc.public_subnet_ids[0]

#   # Attach the security group
#   vpc_security_group_ids = [aws_security_group.bastion_sg.id]

#   # You need a key pair to SSH into the instance
#   # key_name = "your-aws-key-pair-name" 

#   tags = {
#     Name = "${var.project_name}-bastion-host",
#   }

#   user_data = <<-EOF
#               #!/bin/bash
#               # Enable metadata v2 support and fetch public IP
#               TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 3600")
#               PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

#               # Install Apache (if not already installed)
#               apt update -y
#               apt install -y apache2

#               # Create custom index.html with the public IP
#               echo "<html><body><h1>EC2 Public IP: $PUBLIC_IP</h1></body></html>" | tee /var/www/html/index.html > /dev/null

#               # Ensure Apache is enabled and running
#               systemctl enable apache2
#               systemctl restart apache2

#               EOF
# }
