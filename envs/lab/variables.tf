variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "devops-lab"
}

variable "owner" {
  description = "Your name or email - used in the Owner tag"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32. Only this IP can reach SSH and the tool UIs."
  type        = string
}

variable "ssh_public_key" {
  description = "Contents of your public key file, e.g. the output of: cat ~/.ssh/devops-lab.pub"
  type        = string
}

variable "alert_email" {
  description = "Email for AWS Budget alerts"
  type        = string
}

variable "monthly_budget_usd" {
  type    = number
  default = 200
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

# --- Kubernetes ---
variable "cluster_name" {
  type    = string
  default = "devops-lab"
}

variable "kubernetes_version" {
  description = "Start one minor version BELOW the newest EKS version so you can practice an upgrade in Week 2. Check: aws eks describe-cluster-versions"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT (SPOT is ~60-70% cheaper but nodes can be reclaimed)"
  type        = string
  default     = "ON_DEMAND"
}

# --- Database ---
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Flip to true during the HA exercise in Week 2"
  type        = bool
  default     = false
}

# --- Cost guard ---
variable "enable_nightly_stop" {
  description = "Stop all lab EC2 instances every night as a safety net"
  type        = bool
  default     = true
}

variable "timezone" {
  type    = string
  default = "America/Vancouver"
}
