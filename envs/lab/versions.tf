terraform {
  required_version = ">= 1.10, < 2.0" # 1.10 = S3-native locking; < 2.0 = no surprise major release

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73" # floor = the version this lab was written against; the exact build is locked in .terraform.lock.hcl (commit it)
    }
  }

  # Replace the bucket name with the output of the bootstrap step.
  backend "s3" {
    bucket       = "devops-lab-tfstate-201224549118"
    key          = "lab/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true # S3-native state locking (Terraform 1.10+)
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags automatically - cost reports and cleanup depend on them.
  default_tags {
    tags = {
      Project     = var.project
      Environment = "lab"
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
