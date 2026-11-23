# ---------- AWS Backup: daily backups of anything tagged Backup=true ----------
resource "aws_backup_vault" "lab" {
  name          = "${var.project}-vault"
  force_destroy = !var.protect_data # recovery points survive a destroy unless you deliberately allow it
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
