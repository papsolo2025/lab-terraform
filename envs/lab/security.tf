# ---------- Security groups: one per role, least privilege ----------
# Every flow the lab actually uses, and nothing else:
#   you (my_ip_cidr) -> SSH on all servers, Jenkins UI, Nexus/SonarQube UIs, nginx
#   Jenkins          -> SSH on all servers (patching/Ansible jobs), Nexus 8081, SonarQube 9000,
#                       PostgreSQL 5432 (secret sync, DR drill), EKS API 443 (rule in eks.tf)
#   EKS nodes/pods   -> node_exporter 9100 on all servers (Prometheus), PostgreSQL 5432 (orders-api)
# Rules use security groups as the source wherever the caller is an AWS resource, so a new server
# in the VPC gets no access until it is given the right group.

locals {
  server_security_groups = {
    servers = "Shared by every lab server: SSH and node_exporter"
    jenkins = "Jenkins UI"
    tools   = "Nexus and SonarQube"
    web     = "nginx"
  }

  # Inbound from YOUR IP only (lab: servers are public; production: private subnets + SSM/VPN)
  admin_ingress = {
    servers_ssh = { sg = "servers", port = 22 }
    jenkins_ui  = { sg = "jenkins", port = 8080 }
    tools_nexus = { sg = "tools", port = 8081 }
    tools_sonar = { sg = "tools", port = 9000 }
    web_http    = { sg = "web", port = 80 }
  }

  # Inbound from another security group: source = "who is calling"
  sg_ingress = {
    servers_ssh_from_jenkins = { sg = aws_security_group.role["servers"].id, port = 22, source = aws_security_group.role["jenkins"].id, why = "Jenkins runs Ansible patching" }
    servers_metrics_from_eks = { sg = aws_security_group.role["servers"].id, port = 9100, source = module.eks.node_security_group_id, why = "Prometheus scrapes node_exporter" }
    tools_nexus_from_jenkins = { sg = aws_security_group.role["tools"].id, port = 8081, source = aws_security_group.role["jenkins"].id, why = "CI publishes artifacts" }
    tools_sonar_from_jenkins = { sg = aws_security_group.role["tools"].id, port = 9000, source = aws_security_group.role["jenkins"].id, why = "CI quality gate" }
    db_from_eks_nodes        = { sg = aws_security_group.db.id, port = 5432, source = module.eks.node_security_group_id, why = "orders-api pods" }
    db_from_jenkins          = { sg = aws_security_group.db.id, port = 5432, source = aws_security_group.role["jenkins"].id, why = "secret sync and DR drill" }
  }
}

resource "aws_security_group" "role" {
  for_each    = local.server_security_groups
  name        = "${var.project}-${each.key}"
  description = each.value
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project}-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each          = local.admin_ingress
  security_group_id = aws_security_group.role[each.value.sg].id
  description       = "${each.key} from admin IP"
  cidr_ipv4         = var.my_ip_cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each                     = local.sg_ingress
  security_group_id            = each.value.sg
  description                  = each.value.why
  referenced_security_group_id = each.value.source
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# Terraform removes AWS's default allow-all egress rule from every security group it creates,
# so servers need an explicit rule to reach package mirrors, Docker Hub, GitHub and AWS APIs.
# Only the shared group needs it: rules from all of an instance's groups are combined.
# Production: restrict to the destinations you need, or route through a proxy/Network Firewall.
resource "aws_vpc_security_group_egress_rule" "servers_out" {
  security_group_id = aws_security_group.role["servers"].id
  description       = "Outbound for updates, images and AWS APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Database: no egress rule needed - RDS only answers connections, and replies are allowed (stateful).
resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "PostgreSQL from the EKS nodes and Jenkins only"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project}-db" }
}
