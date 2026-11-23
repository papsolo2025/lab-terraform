locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.8.0" # exact pin

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnets  = ["10.20.10.0/24", "10.20.11.0/24"]
  database_subnets = ["10.20.20.0/24", "10.20.21.0/24"]

  create_database_subnet_group = true

  # Database subnets get their own route table with ONLY the local route: no path to the internet at all.
  # (RDS is patched by AWS through its own management network - it never needs NAT.)
  create_database_subnet_route_table = true

  # NAT: one shared gateway by default (cheap). nat_gateway_per_az = true gives each AZ its own,
  # so losing one AZ doesn't cut the other's outbound access (production HA, about +$33/month).
  enable_nat_gateway     = true
  single_nat_gateway     = !var.nat_gateway_per_az
  one_nat_gateway_per_az = var.nat_gateway_per_az

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs (accepted/rejected connections) to CloudWatch - for audits and "was it blocked?" debugging.
  # Off by default to save cost (a few dollars a month); turn on with enable_flow_logs = true.
  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = 7
  flow_log_max_aggregation_interval               = 60

  # Tags the AWS Load Balancer Controller uses to find subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
