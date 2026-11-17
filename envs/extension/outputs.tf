output "exports_bucket" {
  value = aws_s3_bucket.exports.bucket
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "efs_file_system_id" {
  value = aws_efs_file_system.shared.id
}

output "export_processor_function" {
  value = aws_lambda_function.export_processor.function_name
}

output "scheduler_function" {
  value = var.enable_lambda_scheduler ? aws_lambda_function.scheduler[0].function_name : null
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "data_kms_key_arn" {
  value = aws_kms_key.data.arn
}
