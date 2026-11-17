output "servers" {
  description = "Public and private IPs of the lab servers"
  value = {
    for k, s in aws_instance.server : k => {
      public_ip  = s.public_ip
      private_ip = s.private_ip
      id         = s.id
    }
  }
}

output "jenkins_url" {
  value = "http://${aws_instance.server["jenkins"].public_ip}:8080"
}

output "nexus_url" {
  value = "http://${aws_instance.server["tools"].public_ip}:8081"
}

output "sonarqube_url" {
  value = "http://${aws_instance.server["tools"].public_ip}:9000"
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.orders_api.repository_url
}

output "db_endpoint" {
  value = aws_db_instance.orders.address
}

output "db_secret_arn" {
  value = aws_db_instance.orders.master_user_secret[0].secret_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

# ---- Read by the envs/extension stack (terraform_remote_state) ----
output "vpc_cidr" {
  value = var.vpc_cidr
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "jenkins_role_name" {
  value = aws_iam_role.jenkins.name
}

output "db_identifier" {
  value = aws_db_instance.orders.identifier
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}
