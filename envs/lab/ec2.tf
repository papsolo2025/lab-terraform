data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.project}-key"
  public_key = var.ssh_public_key
}

locals {
  # sgs = the role's own security group; every server also gets the shared "servers" group
  servers = {
    jenkins = { type = "t3.medium", disk = 40, role = "jenkins", profile = aws_iam_instance_profile.jenkins.name, backup = "false", sgs = ["jenkins"] }
    tools   = { type = "t3.xlarge", disk = 60, role = "tools", profile = aws_iam_instance_profile.base.name, backup = "true", sgs = ["tools"] }
    web-1   = { type = "t3.micro", disk = 12, role = "web", profile = aws_iam_instance_profile.base.name, backup = "false", sgs = ["web"] }
    web-2   = { type = "t3.micro", disk = 12, role = "web", profile = aws_iam_instance_profile.base.name, backup = "false", sgs = ["web"] }
  }
}

resource "aws_instance" "server" {
  for_each = local.servers

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.value.type
  key_name                    = aws_key_pair.lab.key_name
  iam_instance_profile        = each.value.profile
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true # lab simplification; production uses private subnets + SSM/bastion

  # Least privilege: each server opens only its own ports (e.g. web-1 does not expose 8080)
  vpc_security_group_ids = concat(
    [aws_security_group.role["servers"].id],
    [for sg in each.value.sgs : aws_security_group.role[sg].id],
  )

  root_block_device {
    volume_size = each.value.disk
    volume_type = "gp3"
    encrypted   = true
  }

  # IMDSv2 required. Hop limit 2 lets containers (Jenkins in Docker) use the instance role.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  lifecycle {
    ignore_changes = [ami] # don't rebuild servers every time Canonical publishes a new AMI
  }

  tags = {
    Name       = "${var.project}-${each.key}"
    Role       = each.value.role
    AutoStop   = "true"
    Monitoring = "true"
    Backup     = each.value.backup
  }
}
