# ---------- PostgreSQL for the orders-api ----------
resource "aws_db_instance" "orders" {
  identifier     = "${var.project}-orders-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "orders"
  username                    = "orders_admin"
  manage_master_user_password = true # password lives in Secrets Manager, never in code

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = var.db_multi_az

  backup_retention_period    = 7
  backup_window              = "09:00-09:30" # UTC
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Lab settings so terraform destroy works. Production: deletion_protection = true, final snapshot.
  deletion_protection = false
  skip_final_snapshot = true
}

# ---------- Container registry for runtime images ----------
resource "aws_ecr_repository" "orders_api" {
  name                 = "orders-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # lab only

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "orders_api" {
  repository = aws_ecr_repository.orders_api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ---------- AWS Backup: daily backups of anything tagged Backup=true ----------
resource "aws_backup_vault" "lab" {
  name          = "${var.project}-vault"
  force_destroy = true # lab only
}

resource "aws_backup_plan" "daily" {
  name = "${var.project}-daily"
  rule {
    rule_name         = "daily-7d"
    target_vault_name = aws_backup_vault.lab.name
    schedule          = "cron(0 10 * * ? *)" # 10:00 UTC
    lifecycle {
      delete_after = 7
    }
  }
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.project}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "tagged" {
  name         = "tagged-backup-true"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["*"]
  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = "true"
    }
  }
}
