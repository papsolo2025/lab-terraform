# ---------- Budget alerts: emails you at 50%, 80% and 100% of the monthly budget ----------
resource "aws_budgets_budget" "lab" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}

# ---------- Safety net: stop every lab EC2 instance at 23:00 local time ----------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count              = var.enable_nightly_stop ? 1 : 0
  name               = "${var.project}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enable_nightly_stop ? 1 : 0
  name  = "stop-lab-instances"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StopInstances"]
      Resource = [for s in aws_instance.server : s.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "nightly_stop" {
  count                        = var.enable_nightly_stop ? 1 : 0
  name                         = "${var.project}-nightly-stop"
  schedule_expression          = "cron(0 23 * * ? *)"
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      InstanceIds = [for s in aws_instance.server : s.id]
    })
  }
}
