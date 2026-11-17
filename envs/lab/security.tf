# Admin access from YOUR IP only: SSH and the tool web UIs.
resource "aws_security_group" "admin" {
  name        = "${var.project}-admin-access"
  description = "SSH and tool UIs from the admin IP only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each = {
    ssh     = 22
    http    = 80
    jenkins = 8080
    nexus   = 8081
    sonar   = 9000
  }
  security_group_id = aws_security_group.admin.id
  description       = each.key
  cidr_ipv4         = var.my_ip_cidr
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
}

# Everything inside the VPC can talk to the servers (Jenkins -> Nexus, Prometheus -> node_exporter).
# Lab simplification: production would open only the specific ports.
resource "aws_security_group" "internal" {
  name        = "${var.project}-internal"
  description = "All traffic from inside the VPC"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "internal" {
  security_group_id = aws_security_group.internal.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = { admin = aws_security_group.admin.id, internal = aws_security_group.internal.id }
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Database: PostgreSQL from inside the VPC only.
resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "PostgreSQL from the VPC"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}
