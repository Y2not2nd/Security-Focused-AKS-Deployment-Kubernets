output "aks_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "acr_login_server" {
  description = "ACR login server (for image pushes)"
  value       = azurerm_container_registry.acr.login_server
} 