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

  # Production safeguards (var.protect_data, default true): the database can't be deleted by accident,
  # and a final snapshot is taken if it ever is. Before the Day 17 teardown, apply with protect_data = false.
  deletion_protection       = var.protect_data
  skip_final_snapshot       = !var.protect_data
  final_snapshot_identifier = var.protect_data ? "${var.project}-orders-db-final" : null
  copy_tags_to_snapshot     = true
}
