# Notifications (SNS) and failed-event storage (SQS dead-letter queue)

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = aws_kms_key.data.id
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS sends a confirmation email - click the link
}

# Events that failed after all retries land here instead of being lost.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-lambda-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
  sqs_managed_sse_enabled   = true
}

# ---- Alarms: page a human when automation can't fix it ----
locals {
  lambda_alarm_functions = merge(
    { export = aws_lambda_function.export_processor.function_name },
    var.enable_lambda_scheduler ? { scheduler = aws_lambda_function.scheduler[0].function_name } : {}
  )
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = local.lambda_alarm_functions
  alarm_name          = "${each.value}-errors"
  alarm_description   = "Lambda ${each.value} returned errors. Runbook: lab-ops/runbooks/lambda-errors.md"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${aws_lambda_function.export_processor.function_name}-throttles"
  alarm_description   = "export-processor is being throttled (account concurrency limit?)"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = aws_lambda_function.export_processor.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${aws_sqs_queue.dlq.name}-not-empty"
  alarm_description   = "Events failed after all retries. Inspect and replay: lab-ops ops/replay-dlq job"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
