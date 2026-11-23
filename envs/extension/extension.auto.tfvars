# Environment configuration for the extension stack (LAB) - committed to Git and reviewed in pull requests.
# Personal values are in personal.auto.tfvars (git-ignored). Terraform loads *.auto.tfvars automatically.

region         = "us-west-2"
project        = "devops-lab"
timezone       = "America/Vancouver"
app_namespaces = ["dev", "staging", "prod"]

protect_data = true # false only for the final teardown

# Optional features - enable for the exercises that use them
enable_cloudtrail       = true
enable_guardduty        = false # paid
enable_config           = false # paid (Day 17)
enable_s3_replication   = false # paid; dr_region below
dr_region               = "us-east-1"
enable_lambda_scheduler = false # Day 16
enable_morning_start    = false
