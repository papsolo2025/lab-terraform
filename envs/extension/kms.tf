# Customer managed KMS key for application data (S3 exports, EFS, SNS, SQS).
# Why a CMK instead of the AWS-managed key: you control the key policy, rotation and audit trail,
# and you can revoke access to all the data by disabling one key.
data "aws_iam_policy_document" "data_key" {
  # Let IAM policies in this account grant access to the key (standard first statement)
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  # CloudWatch alarms publish to the encrypted SNS topic
  statement {
    sid       = "CloudWatchAlarmsToEncryptedSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }

  # Everything else (S3, Lambda, EFS, the export CronJob) gets access through IAM policies,
  # which the first statement allows.
}

resource "aws_kms_key" "data" {
  description             = "${local.name} application data"
  enable_key_rotation     = true
  deletion_window_in_days = 7 # lab: shortest allowed so destroy is quick
  policy                  = data.aws_iam_policy_document.data_key.json
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
