terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket-unique-name"
  #   key            = "global/network/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "my-terraform-state-lock-table"
  #   encrypt        = true
  # }

  required_version = ">= 1.2"
}
