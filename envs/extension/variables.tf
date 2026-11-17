# This stack reuses envs/lab/terraform.tfvars (copy it here). Variables that only exist in the
# other stack produce a harmless "undeclared variable" warning.
variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "devops-lab"
}

variable "owner" {
  type = string
}

variable "alert_email" {
  description = "Receives SNS alerts (Lambda errors, DLQ messages, export summaries). Confirm the subscription email."
  type        = string
}

variable "app_namespaces" {
  description = "Kubernetes namespaces whose orders-export job may write to S3"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

# ---- Optional features (toggle in terraform.tfvars) ----
variable "enable_s3_replication" {
  description = "Replicate exports to a bucket in dr_region (Day 16 exercise)"
  type        = bool
  default     = false
}

variable "dr_region" {
  type    = string
  default = "us-east-1"
}

variable "enable_lambda_scheduler" {
  description = "Stop the lab every night with the scheduler Lambda (set enable_nightly_stop = false in the lab stack when you turn this on)"
  type        = bool
  default     = false
}

variable "enable_morning_start" {
  description = "Also start the lab at 08:00 on weekdays"
  type        = bool
  default     = false
}

variable "timezone" {
  type    = string
  default = "America/Vancouver"
}

variable "enable_cloudtrail" {
  description = "Multi-region CloudTrail trail (first trail of management events is free; you pay a little for S3)"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "GuardDuty threat detection (30-day free trial for new accounts; turn off after the lab)"
  type        = bool
  default     = false
}

variable "enable_config" {
  description = "AWS Config recording security groups + S3 buckets with 3 managed rules (small per-item cost)"
  type        = bool
  default     = false
}
