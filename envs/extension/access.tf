# ---------- orders-export CronJob (Kubernetes) -> S3, via EKS Pod Identity ----------
# One IAM role for all environments, but each namespace may only write under its own prefix:
# Pod Identity adds the session tag kubernetes-namespace, and the policy uses it (ABAC).
# dev can never overwrite prod's exports - and there are no access keys anywhere.
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "orders_export" {
  name               = "${local.name}-orders-export"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "orders_export" {
  name = "write-own-namespace-prefix"
  role = aws_iam_role.orders_export.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "WriteOwnPrefixOnly", Effect = "Allow", Action = ["s3:PutObject"],
      Resource = "${aws_s3_bucket.exports.arn}/exports/$${aws:PrincipalTag/kubernetes-namespace}/*" },
      { Sid = "EncryptWithDataKey", Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = aws_kms_key.data.arn },
    ]
  })
}

resource "aws_eks_pod_identity_association" "orders_export" {
  for_each        = toset(var.app_namespaces)
  cluster_name    = local.lab.cluster_name
  namespace       = each.value
  service_account = "orders-export"
  role_arn        = aws_iam_role.orders_export.arn
}

# ---------- Jenkins: deploy Lambda code, run smoke tests, replay the DLQ ----------
resource "aws_iam_role_policy" "jenkins_serverless" {
  name = "jenkins-serverless"
  role = local.lab.jenkins_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "DeployLabFunctions", Effect = "Allow",
        Action = ["lambda:UpdateFunctionCode", "lambda:PublishVersion", "lambda:UpdateAlias", "lambda:GetAlias",
          "lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:InvokeFunction",
        "lambda:ListVersionsByFunction", "lambda:ListAliases"],
      Resource = ["arn:aws:lambda:${var.region}:${local.account_id}:function:${local.name}-*"] },
      { Sid = "UploadPackages", Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"],
      Resource = "${aws_s3_bucket.artifacts.arn}/*" },
      { Sid = "SmokeTestFiles", Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"],
      Resource = ["${aws_s3_bucket.exports.arn}/smoke/*", "${aws_s3_bucket.exports.arn}/summaries/smoke/*"] },
      { Sid = "SmokeTestKey", Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = aws_kms_key.data.arn },
      { Sid = "ReplayDlq", Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
      Resource = aws_sqs_queue.dlq.arn },
      { Sid = "ReadLogs", Effect = "Allow", Action = ["logs:FilterLogEvents"], Resource = "*" },
    ]
  })
}
