output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "registry_repository" { value = aws_ecr_repository.app.repository_url }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
