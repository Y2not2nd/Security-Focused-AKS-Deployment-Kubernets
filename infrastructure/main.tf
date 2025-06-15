resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.50.0.0/16"]
  location           = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "aks" {
  name                = "${var.prefix}-aks-subnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes    = ["10.50.0.0/22"]  # Subnet for AKS nodes (and pods, since using Azure CNI)
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = "1.24.9"  # or latest available stable version
  dns_prefix         = "${var.prefix}-aks"   # used for AKS DNS name
  
  # Configure public access to API server
  api_server_access_profile {
    authorized_ip_ranges = ["0.0.0.0/0"]  # Allow access from any IP (for demo purposes)
  }

  default_node_pool {
    name           = "system"
    node_count     = 3
    vm_size        = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.aks.id
    type           = "VirtualMachineScaleSets"
    node_labels = {
      "agentpool" = "system"
    }
  }

  identity {
    type = "SystemAssigned"  # use a managed identity for the AKS control plane
  }

  network_profile {
    network_plugin     = "azure"   # Azure CNI (pods get VNet IPs)
    network_policy     = "azure"   # enable Azure network policies (or "calico")
    load_balancer_sku  = "standard"
    service_cidr       = "10.0.0.0/16"       # Cluster IPs for services
    dns_service_ip     = "10.0.0.10"         # DNS service IP within service CIDR
    outbound_type      = "loadBalancer"      # Outbound traffic uses standard LB
  }

  # Remove private cluster settings
  private_cluster_enabled = false

  azure_active_directory_role_based_access_control {
    admin_group_object_ids = [var.admin_group_object_id]
    azure_rbac_enabled     = true
  }

  local_account_disabled = true            # Keep Kubernetes admin user disabled, use Azure AD

  tags = {
    Environment = "Demo"
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix}acr"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                = "Standard"
  admin_enabled      = false    # disable admin user, use AAD integration
}

# Grant AKS permission to pull from ACR (AcrPull role)
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
} 