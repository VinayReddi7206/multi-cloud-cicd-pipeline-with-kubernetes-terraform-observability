output "cluster_name" { value = azurerm_kubernetes_cluster.main.name }
output "resource_group_name" { value = azurerm_resource_group.main.name }
output "registry_name" { value = azurerm_container_registry.app.name }
output "registry_repository" { value = "${azurerm_container_registry.app.login_server}/multicloud-app" }
output "virtual_network_id" { value = azurerm_virtual_network.main.id }
