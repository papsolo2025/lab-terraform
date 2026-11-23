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
  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty - it becomes the Owner tag on every resource."
  }
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32. Only this IP can reach SSH and the tool UIs."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.my_ip_cidr)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "my_ip_cidr must be a CIDR such as 203.0.113.10/32 (not 0.0.0.0/0 - that would open the admin ports to the internet)."
  }
}

variable "ssh_public_key" {
  description = "Contents of your public key file, e.g. the output of: cat ~/.ssh/devops-lab.pub"
  type        = string
  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.ssh_public_key))
    error_message = "ssh_public_key must be the contents of a .pub file (starts with ssh-ed25519, ssh-rsa or ecdsa-sha2-nistp256). Never paste the private key."
  }
}

variable "alert_email" {
  description = "Email for AWS Budget alerts"
  type        = string
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  type    = number
  default = 200
  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than 0."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be a valid CIDR of /16 or larger (the subnets are carved out of 10.20.0.0/16)."
  }
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
  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36 (major.minor only)."
  }
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT (SPOT is ~60-70% cheaper but nodes can be reclaimed)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
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

# --- Production safeguards (free) ---
variable "protect_data" {
  description = "Production-style protection: RDS deletion protection + final snapshot, and no force-delete on ECR or the backup vault. Set to false (and apply) only right before terraform destroy."
  type        = bool
  default     = true
}

# --- Paid production options (off by default; turn on for the HA / audit exercises) ---
variable "nat_gateway_per_az" {
  description = "One NAT gateway per AZ instead of one shared (HA). About +$33/month per extra NAT."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "VPC Flow Logs to CloudWatch (7-day retention). A few dollars a month."
  type        = bool
  default     = false
}
