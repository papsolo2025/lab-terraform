# lab-terraform
All AWS infrastructure for the DevOps lab, as code.

- `bootstrap/` - S3 bucket for remote state (run once, local state)
- `envs/lab/` - VPC, EC2 servers, EKS (+ add-ons, Pod Identity), RDS PostgreSQL, ECR, IAM, AWS Backup, budget alerts, nightly stop schedule

```bash
cd envs/lab
cp terraform.tfvars.example terraform.tfvars   # fill in - never commit
terraform init && terraform plan -out tfplan && terraform apply tfplan
```
