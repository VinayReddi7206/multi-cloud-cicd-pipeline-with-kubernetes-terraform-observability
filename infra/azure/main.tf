locals {
  name = "${var.project}-${var.environment}"
  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
data "azurerm_client_config" "current" {}
resource "azurerm_resource_group" "main" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 6, 0)]
}
resource "azurerm_container_registry" "app" {
  # checkov:skip=CKV_AZURE_237:Standard SKU learning registry; dedicated Premium data endpoints are out of scope. See docs/security.md.
  # checkov:skip=CKV_AZURE_166:Images are scanned before push; ACR quarantine is not configured. See docs/security.md.
  # checkov:skip=CKV_AZURE_167:Premium retention is not available on this Standard registry; cleanup is an operator task. See docs/security.md.
  # checkov:skip=CKV_AZURE_233:This single-region exercise does not use Premium ACR zone redundancy. See docs/security.md.
  # checkov:skip=CKV_AZURE_165:Each cloud has one regional registry; geo-replication is outside the exercise. See docs/security.md.
  # checkov:skip=CKV_AZURE_139:Authenticated public registry endpoint is required by the hosted publishing runner. See docs/security.md.
  # checkov:skip=CKV_AZURE_164:Digest-based deployment is implemented; image signing and trust enforcement are outstanding. See docs/security.md.
  name                   = var.acr_name
  resource_group_name    = azurerm_resource_group.main.name
  location               = var.location
  sku                    = "Standard"
  admin_enabled          = false
  anonymous_pull_enabled = false
  tags                   = local.tags
}
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name}-logs"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.name}-aks-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_role_assignment" "network" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}
resource "azurerm_kubernetes_cluster" "main" {
  # checkov:skip=CKV_AZURE_226:Managed OS disks support the selected VM sizes; ephemeral OS storage is not required. See docs/security.md.
  # checkov:skip=CKV_AZURE_170:Production selects Standard; Dev and Staging intentionally use the Free management tier. See docs/security.md.
  # checkov:skip=CKV_AZURE_232:This learning cluster shares its node pool with application pods. See docs/security.md.
  # checkov:skip=CKV_AZURE_117:Platform-managed disk encryption is used; a customer-managed disk encryption set is not configured. See docs/security.md.
  name                              = "${local.name}-aks"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.name
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = var.environment == "production" ? "Standard" : "Free"
  private_cluster_enabled           = true
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = true
  automatic_upgrade_channel         = "patch"
  default_node_pool {
    name                    = "system"
    vm_size                 = var.node_vm_size
    node_count              = var.node_count
    vnet_subnet_id          = azurerm_subnet.aks.id
    os_disk_size_gb         = 64
    max_pods                = 50
    host_encryption_enabled = true
    upgrade_settings { max_surge = "33%" }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.30.0.0/16"
    dns_service_ip      = "10.30.0.10"
    load_balancer_sku   = "standard"
  }
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
  depends_on = [azurerm_role_assignment.network]
  tags       = local.tags
}
resource "azurerm_network_security_group" "aks" {
  name                = "${local.name}-aks-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
resource "azurerm_role_assignment" "pull" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
resource "azurerm_role_assignment" "push" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPush"
  principal_id         = var.deployer_object_id
}
resource "azurerm_role_assignment" "cluster_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.deployer_object_id
}
resource "azurerm_role_assignment" "cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.deployer_object_id
}
