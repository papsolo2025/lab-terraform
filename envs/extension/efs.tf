# Shared file storage (EFS): many pods in different AZs read/write the same files (ReadWriteMany).
# Compare with EBS (one node at a time, one AZ) used by Prometheus, and S3 (objects over an API).
resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "NFS from the EKS nodes only"
  vpc_id      = local.lab.vpc_id
}

# Only the EKS nodes (where the pods mounting EFS run) may reach NFS - not every resource in the VPC.
resource "aws_vpc_security_group_ingress_rule" "efs_nfs" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from EKS nodes"
  referenced_security_group_id = local.lab.node_security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_efs_file_system" "shared" {
  creation_token   = "${local.name}-shared"
  encrypted        = true
  kms_key_id       = aws_kms_key.data.arn
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic" # pay for what you use, scales automatically

  # Move files nobody reads to the cheaper Infrequent Access class; bring them back when read
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name   = "${local.name}-shared"
    Backup = "true" # picked up by the AWS Backup plan from the lab stack
  }
}

# One mount target per AZ = the file system stays reachable if an AZ fails
resource "aws_efs_mount_target" "shared" {
  for_each        = toset(local.lab.private_subnet_ids)
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# Require TLS for every client (the EFS CSI driver mounts with TLS by default)
data "aws_iam_policy_document" "efs" {
  statement {
    sid     = "AllowMountThroughMountTargets"
    actions = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_efs_file_system.shared.arn]
    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }
  statement {
    sid     = "DenyUnencryptedTransport"
    effect  = "Deny"
    actions = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_efs_file_system.shared.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_efs_file_system_policy" "shared" {
  file_system_id = aws_efs_file_system.shared.id
  policy         = data.aws_iam_policy_document.efs.json
}

# ---- EFS CSI driver add-on (Kubernetes creates EFS access points for each PVC) ----
module "efs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.11.0"

  name                      = "${local.name}-efs-csi"
  attach_aws_efs_csi_policy = true
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name = local.lab.cluster_name
  addon_name   = "aws-efs-csi-driver"

  pod_identity_association {
    role_arn        = module.efs_csi_pod_identity.iam_role_arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [aws_efs_mount_target.shared]
}
