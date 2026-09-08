variable "project" {
  type    = string
  default = "multicloud"
}
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Choose dev, staging, or production."
  }
}
variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "node_instance_type" {
  type    = string
  default = "t3.large"
}
variable "node_count" {
  type    = number
  default = 2
  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive integer."
  }
}
variable "deployer_role_arn" {
  description = "Existing GitHub OIDC deployment role. Provision this during identity bootstrap."
  type        = string
}
variable "provisioner_role_arn" {
  description = "Existing Terraform apply role; explicit KMS administrator independent of the planning caller."
  type        = string
}
