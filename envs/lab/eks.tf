module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Public endpoint for your laptop only; everything inside the VPC (nodes, Jenkins) uses the private endpoint.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.my_ip_cidr]
  endpoint_private_access      = true

  # Allow Jenkins (in the VPC, different security group) to reach the private API endpoint.
  security_group_additional_rules = {
    ingress_vpc_https = {
      description = "Kubernetes API from inside the VPC"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  # The IAM identity that runs terraform apply becomes cluster admin.
  enable_cluster_creator_admin_permissions = true

  # Never silently roll into paid Extended Support (6x the price).
  upgrade_policy = {
    support_type = "STANDARD"
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      capacity_type  = var.node_capacity_type

      min_size     = 1
      max_size     = 4
      desired_size = 2
    }
  }

  # Let Jenkins deploy to the cluster.
  # Lab simplification: cluster admin. Production: namespace-scoped AmazonEKSEditPolicy.
  access_entries = {
    jenkins = {
      principal_arn = aws_iam_role.jenkins.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

# IAM for the EBS CSI driver (persistent volumes for Prometheus/Grafana)
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}

# IAM for the AWS Load Balancer Controller (creates ALBs from Ingress objects)
module "aws_lbc_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${var.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}
