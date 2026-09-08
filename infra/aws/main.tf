locals {
  name = "${var.project}-${var.environment}"
  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
data "aws_availability_zones" "available" {
  state = "available"
}
module "vpc" {
  # terraform-aws-vpc v6.0.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=a0307d4d1807de60b3868b96ef1b369808289157"

  name                                            = local.name
  cidr                                            = var.vpc_cidr
  azs                                             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets                                 = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets                                  = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]
  enable_nat_gateway                              = true
  single_nat_gateway                              = var.environment != "production"
  enable_dns_hostnames                            = true
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 30
  private_subnet_tags                             = { "kubernetes.io/role/internal-elb" = "1" }
  public_subnet_tags                              = { "kubernetes.io/role/elb" = "1" }
  tags                                            = local.tags
}

resource "aws_iam_role" "ebs" {
  name = "${local.name}-ebs-csi"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ebs" {
  role       = aws_iam_role.ebs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "eks" {
  # terraform-aws-eks v21.0.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=b7eabbd3848f09e62add631e0c7683b7db0db8b9"

  name                                     = local.name
  kubernetes_version                       = var.kubernetes_version
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  endpoint_private_access                  = true
  endpoint_public_access                   = false
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  enabled_log_types                        = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  enable_kms_key_rotation                  = true
  kms_key_administrators                   = [var.provisioner_role_arn]
  upgrade_policy                           = { support_type = "STANDARD" }
  access_entries = {
    deployer = {
      principal_arn = var.deployer_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
  security_group_additional_rules = {
    private_runners = {
      description = "Kubernetes API access for authenticated runners in the project VPC"
      type        = "ingress"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = [var.vpc_cidr]
    }
  }
  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute       = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }
  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = var.node_count
      max_size       = var.node_count + 2
      desired_size   = var.node_count
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 40
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
  depends_on = [aws_iam_role_policy_attachment.ebs]
  tags       = local.tags
}

data "aws_caller_identity" "current" {}
resource "aws_kms_key" "registry" {
  description             = "${local.name} registry encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableAccountIAMPermissions"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}
resource "aws_ecr_repository" "app" {
  name                 = "${local.name}/app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.registry.arn
  }
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images after seven days; preserve tagged rollback images."
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
      action       = { type = "expire" }
    }]
  })
}
