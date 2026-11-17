# Governance and detective controls: who did what (CloudTrail), threats (GuardDuty),
# configuration compliance (AWS Config) - including the security-group blind spot from Day 9.

resource "aws_s3_bucket" "audit" {
  count         = var.enable_cloudtrail || var.enable_config ? 1 : 0
  bucket        = "${local.name}-audit-logs-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "audit" {
  count                   = length(aws_s3_bucket.audit)
  bucket                  = aws_s3_bucket.audit[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  count  = length(aws_s3_bucket.audit)
  bucket = aws_s3_bucket.audit[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  count  = length(aws_s3_bucket.audit)
  bucket = aws_s3_bucket.audit[0].id
  rule {
    id     = "expire-audit-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90 # production: years, often with Object Lock for tamper-proof retention
    }
  }
}

data "aws_iam_policy_document" "audit" {
  count = length(aws_s3_bucket.audit)

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.audit[0].arn, "${aws_s3_bucket.audit[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "ServicesCheckBucketAcl"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.audit[0].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com", "config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid     = "ServicesWriteLogs"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.audit[0].arn}/cloudtrail/AWSLogs/${local.account_id}/*",
      "${aws_s3_bucket.audit[0].arn}/config/AWSLogs/${local.account_id}/*",
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com", "config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  count      = length(aws_s3_bucket.audit)
  bucket     = aws_s3_bucket.audit[0].id
  policy     = data.aws_iam_policy_document.audit[0].json
  depends_on = [aws_s3_bucket_public_access_block.audit]
}

# ---------- CloudTrail: every API call in every region, with tamper-evident log files ----------
resource "aws_cloudtrail" "lab" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "${local.name}-trail"
  s3_bucket_name                = aws_s3_bucket.audit[0].id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.audit]
}

# ---------- GuardDuty: threat detection from CloudTrail, VPC flow and DNS logs ----------
resource "aws_guardduty_detector" "lab" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}

# ---------- AWS Config: continuous compliance for security groups and S3 buckets ----------
resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0
  name  = "${local.name}-config"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "config.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "lab" {
  count    = var.enable_config ? 1 : 0
  name     = "${local.name}-recorder"
  role_arn = aws_iam_role.config[0].arn
  recording_group {
    all_supported  = false
    resource_types = ["AWS::EC2::SecurityGroup", "AWS::S3::Bucket"] # small scope = small bill
  }
}

resource "aws_config_delivery_channel" "lab" {
  count          = var.enable_config ? 1 : 0
  name           = "${local.name}-delivery"
  s3_bucket_name = aws_s3_bucket.audit[0].id
  s3_key_prefix  = "config"
  depends_on     = [aws_config_configuration_recorder.lab, aws_s3_bucket_policy.audit]
}

resource "aws_config_configuration_recorder_status" "lab" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.lab[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.lab]
}

locals {
  config_rules = var.enable_config ? {
    # Catches the "temporary" 0.0.0.0/0 rule from the Day 9 drift drill that terraform plan cannot see
    sg-open-only-to-authorized-ports = { id = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS", params = jsonencode({ authorizedTcpPorts = "443" }) }
    s3-bucket-public-read-prohibited = { id = "S3_BUCKET_PUBLIC_READ_PROHIBITED", params = null }
    s3-bucket-ssl-requests-only      = { id = "S3_BUCKET_SSL_REQUESTS_ONLY", params = null }
  } : {}
}

resource "aws_config_config_rule" "lab" {
  for_each         = local.config_rules
  name             = "${local.name}-${each.key}"
  input_parameters = each.value.params
  source {
    owner             = "AWS"
    source_identifier = each.value.id
  }
  depends_on = [aws_config_configuration_recorder_status.lab]
}
