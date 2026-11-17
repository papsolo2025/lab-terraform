# Extension stack: storage, serverless and governance.
# Separate state from envs/lab on purpose: different lifecycle, smaller blast radius,
# faster plans. It reads what it needs from the lab stack's outputs (terraform_remote_state).
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket       = "devops-lab-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key          = "extension/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = "lab"
      Owner       = var.owner
      ManagedBy   = "terraform"
      Stack       = "extension"
    }
  }
}

# Second region for S3 cross-region replication (disaster recovery)
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = "lab"
      Owner       = var.owner
      ManagedBy   = "terraform"
      Stack       = "extension"
    }
  }
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "lab" {
  backend = "s3"
  config = {
    bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key    = "lab/terraform.tfstate"
    region = var.region
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  lab        = data.terraform_remote_state.lab.outputs
  name       = var.project
}
