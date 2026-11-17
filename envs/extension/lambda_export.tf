# export-processor: S3 event -> validate export -> write summary -> notify.
# Terraform owns the INFRASTRUCTURE (role, triggers, retries, DLQ, logs, alias).
# The lab-serverless Jenkins pipeline owns the CODE (uploads a zip, publishes a version, moves the alias).

data "archive_file" "placeholder" {
  type        = "zip"
  source_file = "${path.module}/lambda-placeholder/app.py"
  output_path = "${path.module}/.build/placeholder.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "export_processor" {
  name               = "${local.name}-export-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "export_processor_basic" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole", # CloudWatch Logs
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",                 # tracing
  ])
  role       = aws_iam_role.export_processor.name
  policy_arn = each.value
}

# Least privilege: read only the input prefixes, write only the output prefixes.
resource "aws_iam_role_policy" "export_processor" {
  name = "export-processor"
  role = aws_iam_role.export_processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadInputs", Effect = "Allow", Action = ["s3:GetObject"],
      Resource = ["${aws_s3_bucket.exports.arn}/exports/*", "${aws_s3_bucket.exports.arn}/smoke/*"] },
      { Sid = "WriteOutputs", Effect = "Allow", Action = ["s3:PutObject"],
      Resource = ["${aws_s3_bucket.exports.arn}/summaries/*", "${aws_s3_bucket.exports.arn}/quarantine/*"] },
      { Sid = "UseDataKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.data.arn },
      { Sid = "Notify", Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn },
      { Sid = "FailureDestination", Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.dlq.arn },
    ]
  })
}

resource "aws_cloudwatch_log_group" "export_processor" {
  name              = "/aws/lambda/${local.name}-export-processor"
  retention_in_days = 14 # logs kept forever by default = slow-growing cost
}

resource "aws_lambda_function" "export_processor" {
  function_name = "${local.name}-export-processor"
  description   = "Validates order exports from S3, writes summaries, notifies"
  role          = aws_iam_role.export_processor.arn
  runtime       = "python3.13"
  handler       = "app.handler"
  architectures = ["arm64"] # Graviton: lower price per GB-second and less energy
  memory_size   = 256
  timeout       = 30
  publish       = true

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.export_processor.name
  }

  # The pipeline deploys new code; Terraform must not roll it back to the placeholder.
  lifecycle {
    ignore_changes = [filename, source_code_hash, s3_bucket, s3_key, s3_object_version]
  }

  depends_on = [aws_iam_role_policy_attachment.export_processor_basic]
}

# Callers (S3) always invoke the "live" alias. Deploy = point the alias at a new version.
# Rollback = point it back. No re-upload, takes a second.
resource "aws_lambda_alias" "export_live" {
  name             = "live"
  function_name    = aws_lambda_function.export_processor.function_name
  function_version = aws_lambda_function.export_processor.version

  lifecycle {
    ignore_changes = [function_version] # moved by the pipeline
  }
}

# Asynchronous invocations (S3 events): 2 retries, then send the event to the DLQ.
resource "aws_lambda_function_event_invoke_config" "export_live" {
  function_name                = aws_lambda_function.export_processor.function_name
  qualifier                    = aws_lambda_alias.export_live.name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}

resource "aws_lambda_permission" "s3_invoke_export" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.export_processor.function_name
  qualifier      = aws_lambda_alias.export_live.name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.exports.arn
  source_account = local.account_id
}
