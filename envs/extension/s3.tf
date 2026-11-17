# ===================== Exports bucket (application data) =====================
# Layout:  exports/<namespace>/orders-YYYY-MM-DD.json   written by the orders-export CronJob
#          summaries/...                                  written by the export-processor Lambda
#          quarantine/...                                 invalid files moved aside by the Lambda
#          smoke/...                                      test files used by the Lambda pipeline
resource "aws_s3_bucket" "exports" {
  bucket        = "${local.name}-orders-exports-${local.account_id}"
  force_destroy = true # lab only
}

resource "aws_s3_bucket_ownership_controls" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    object_ownership = "BucketOwnerEnforced" # ACLs disabled - access is controlled by IAM/bucket policy only
  }
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "exports" {
  bucket = aws_s3_bucket.exports.id
  versioning_configuration {
    status = "Enabled" # protects against accidental overwrite/delete; required for replication
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true # cuts KMS request costs by up to 99%
  }
}

# Deny any request that is not over TLS (data in transit)
data "aws_iam_policy_document" "exports_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.exports.arn,
      "${aws_s3_bucket.exports.arn}/*",
    ]
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
}

resource "aws_s3_bucket_policy" "exports" {
  bucket     = aws_s3_bucket.exports.id
  policy     = data.aws_iam_policy_document.exports_tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.exports]
}

# Storage classes by age: the cost pillar in one resource
resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    id     = "exports-tiering"
    status = "Enabled"
    filter {
      prefix = "exports/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = 730
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "short-lived-prefixes"
    status = "Enabled"
    filter {
      prefix = "smoke/"
    }
    expiration {
      days = 7
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.exports]
}

# New export file -> export-processor Lambda (through the "live" alias, so deployments are safe)
resource "aws_s3_bucket_notification" "exports" {
  bucket = aws_s3_bucket.exports.id

  lambda_function {
    lambda_function_arn = aws_lambda_alias.export_live.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "exports/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.s3_invoke_export]
}

# ===================== Artifacts bucket (Lambda deployment packages) =====================
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-lambda-artifacts-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-packages"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
  depends_on = [aws_s3_bucket_versioning.artifacts]
}

# ===================== S3 gateway endpoint =====================
# Traffic from private subnets (EKS pods) to S3 stays on the AWS network and skips the NAT gateway:
# no NAT data-processing charge (cost) and no internet path (security). Gateway endpoints are free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.lab.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.lab.private_route_table_ids
  tags = {
    Name = "${local.name}-s3-gateway"
  }
}

# ===================== Cross-region replication (optional, DR) =====================
resource "aws_kms_key" "dr" {
  count                   = var.enable_s3_replication ? 1 : 0
  provider                = aws.dr
  description             = "${local.name} replica data (DR region)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "exports_replica" {
  count         = var.enable_s3_replication ? 1 : 0
  provider      = aws.dr
  bucket        = "${local.name}-orders-exports-replica-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "exports_replica" {
  count    = var.enable_s3_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.exports_replica[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "exports_replica" {
  count                   = var.enable_s3_replication ? 1 : 0
  provider                = aws.dr
  bucket                  = aws_s3_bucket.exports_replica[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count              = var.enable_s3_replication ? 1 : 0
  name               = "${local.name}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_s3_replication ? 1 : 0
  name  = "replicate-exports"
  role  = aws_iam_role.replication[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"], Resource = aws_s3_bucket.exports.arn },
      { Effect = "Allow", Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"], Resource = "${aws_s3_bucket.exports.arn}/*" },
      { Effect = "Allow", Action = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"], Resource = "${aws_s3_bucket.exports_replica[0].arn}/*" },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = aws_kms_key.data.arn },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.dr[0].arn },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "exports" {
  count  = var.enable_s3_replication ? 1 : 0
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.exports.id

  rule {
    id     = "exports-to-dr"
    status = "Enabled"
    filter {
      prefix = "exports/"
    }
    delete_marker_replication {
      status = "Enabled"
    }
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
    destination {
      bucket        = aws_s3_bucket.exports_replica[0].arn
      storage_class = "STANDARD_IA"
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr[0].arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.exports, aws_s3_bucket_versioning.exports_replica]
}
