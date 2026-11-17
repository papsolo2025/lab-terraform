locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnets  = ["10.20.10.0/24", "10.20.11.0/24"]
  database_subnets = ["10.20.20.0/24", "10.20.21.0/24"]

  create_database_subnet_group = true

  # One NAT gateway keeps the lab cheap. Production uses one per AZ (see Week 2 HA exercise).
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags the AWS Load Balancer Controller uses to find subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
