data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------- Base role: every server (Session Manager access only) ----------
resource "aws_iam_role" "base" {
  name               = "${var.project}-base-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "base_ssm" {
  role       = aws_iam_role.base.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "base" {
  name = "${var.project}-base-ec2"
  role = aws_iam_role.base.name
}

# ---------- Jenkins role: runs CI/CD and all the automation jobs ----------
resource "aws_iam_role" "jenkins" {
  name               = "${var.project}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/ReadOnlyAccess",                      # drift checks, cost/idle reports, inventories
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser", # push images to ECR
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.jenkins.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "jenkins_extra" {
  # Terraform drift check needs to write/delete the S3 lock file
  statement {
    sid       = "TerraformStateLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}/*.tflock"]
  }

  # Weekly cost report
  statement {
    sid       = "CostExplorer"
    actions   = ["ce:GetCostAndUsage", "ce:GetCostForecast"]
    resources = ["*"]
  }

  # Monthly access review
  statement {
    sid       = "CredentialReport"
    actions   = ["iam:GenerateCredentialReport", "iam:GetCredentialReport"]
    resources = ["*"]
  }

  # Read the DB password (to create the Kubernetes secret and for the DR drill)
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.orders.master_user_secret[0].secret_arn]
  }

  # Monthly DR drill: restore a snapshot into a temporary dr-* instance, then delete it
  statement {
    sid = "DrDrillRestore"
    actions = [
      "rds:RestoreDBInstanceFromDBSnapshot",
      "rds:AddTagsToResource",
      "rds:CreateDBInstance",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "DrDrillDelete"
    actions   = ["rds:DeleteDBInstance"]
    resources = ["arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:dr-*"]
  }
}

resource "aws_iam_role_policy" "jenkins_extra" {
  name   = "jenkins-automation"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_extra.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-jenkins"
  role = aws_iam_role.jenkins.name
}
