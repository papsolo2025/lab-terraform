# lab-scheduler: EventBridge Scheduler -> Lambda that stops (and optionally starts) the whole lab:
# EC2 servers tagged AutoStop=true, the RDS database, and the EKS node groups.
# Replaces the simpler EC2-only schedule in the lab stack (set enable_nightly_stop = false there).

resource "aws_iam_role" "scheduler_fn" {
  count              = var.enable_lambda_scheduler ? 1 : 0
  name               = "${local.name}-lab-scheduler"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "scheduler_fn_basic" {
  count      = var.enable_lambda_scheduler ? 1 : 0
  role       = aws_iam_role.scheduler_fn[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "scheduler_fn" {
  count = var.enable_lambda_scheduler ? 1 : 0
  name  = "stop-start-lab"
  role  = aws_iam_role.scheduler_fn[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "FindInstances", Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*" },
      # Can only stop/start instances that carry the lab's Project tag (attribute-based access control)
      { Sid      = "StopStartLabInstancesOnly", Effect = "Allow", Action = ["ec2:StopInstances", "ec2:StartInstances"],
        Resource = "arn:aws:ec2:${var.region}:${local.account_id}:instance/*",
      Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project } } },
      { Sid = "Database", Effect = "Allow", Action = ["rds:DescribeDBInstances", "rds:StopDBInstance", "rds:StartDBInstance"],
      Resource = "arn:aws:rds:${var.region}:${local.account_id}:db:${local.lab.db_identifier}" },
      { Sid = "NodeGroups", Effect = "Allow", Action = ["eks:ListNodegroups", "eks:DescribeNodegroup", "eks:UpdateNodegroupConfig"],
        Resource = [local.lab.cluster_arn,
      "arn:aws:eks:${var.region}:${local.account_id}:nodegroup/${local.lab.cluster_name}/*/*"] },
    ]
  })
}

resource "aws_cloudwatch_log_group" "scheduler_fn" {
  count             = var.enable_lambda_scheduler ? 1 : 0
  name              = "/aws/lambda/${local.name}-lab-scheduler"
  retention_in_days = 14
}

resource "aws_lambda_function" "scheduler" {
  count         = var.enable_lambda_scheduler ? 1 : 0
  function_name = "${local.name}-lab-scheduler"
  description   = "Stops/starts the lab: EC2 (AutoStop tag), RDS, EKS node groups"
  role          = aws_iam_role.scheduler_fn[0].arn
  runtime       = "python3.13"
  handler       = "app.handler"
  architectures = ["arm64"]
  memory_size   = 128
  timeout       = 120
  publish       = true

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      PROJECT      = var.project
      CLUSTER_NAME = local.lab.cluster_name
      DB_INSTANCE  = local.lab.db_identifier
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.scheduler_fn[0].name
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash, s3_bucket, s3_key, s3_object_version]
  }

  depends_on = [aws_iam_role_policy_attachment.scheduler_fn_basic]
}

resource "aws_lambda_alias" "scheduler_live" {
  count            = var.enable_lambda_scheduler ? 1 : 0
  name             = "live"
  function_name    = aws_lambda_function.scheduler[0].function_name
  function_version = aws_lambda_function.scheduler[0].version
  lifecycle {
    ignore_changes = [function_version]
  }
}

# ---- EventBridge Scheduler -> Lambda alias ----
data "aws_iam_policy_document" "eb_scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eb_scheduler" {
  count              = var.enable_lambda_scheduler ? 1 : 0
  name               = "${local.name}-eb-scheduler-invoke"
  assume_role_policy = data.aws_iam_policy_document.eb_scheduler_assume.json
}

resource "aws_iam_role_policy" "eb_scheduler" {
  count = var.enable_lambda_scheduler ? 1 : 0
  name  = "invoke-lab-scheduler"
  role  = aws_iam_role.eb_scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_alias.scheduler_live[0].arn },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.dlq.arn },
    ]
  })
}

locals {
  lab_schedules = var.enable_lambda_scheduler ? {
    stop  = { cron = "cron(0 23 * * ? *)", state = "ENABLED" }
    start = { cron = "cron(0 8 ? * MON-FRI *)", state = var.enable_morning_start ? "ENABLED" : "DISABLED" }
  } : {}
}

resource "aws_scheduler_schedule" "lab" {
  for_each                     = local.lab_schedules
  name                         = "${local.name}-lab-${each.key}"
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.timezone
  state                        = each.value.state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.scheduler_live[0].arn
    role_arn = aws_iam_role.eb_scheduler[0].arn
    input    = jsonencode({ action = each.key, dry_run = false })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
    dead_letter_config {
      arn = aws_sqs_queue.dlq.arn
    }
  }
}
