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
variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "centralindia"
}
variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "acr_name" {
  description = "Globally unique registry name: lowercase letters and digits, 5-50 characters."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "ACR name must contain 5-50 lowercase letters or digits."
  }
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "node_count" {
  type    = number
  default = 2
  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive integer."
  }
}
variable "deployer_object_id" {
  description = "Object ID (not client ID) of the existing GitHub OIDC deployment service principal."
  type        = string
}
