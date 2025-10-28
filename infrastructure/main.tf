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
  address_prefixes    = ["10.50.0.0/22"]  
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = "1.31.8" 
  dns_prefix         = "${var.prefix}-aks"
  sku_tier           = "Free"    
  
  # Configure public access to API server
  api_server_access_profile {
    authorized_ip_ranges = ["0.0.0.0/0"]  
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
    type = "SystemAssigned"  
  }

  network_profile {
    network_plugin     = "azure"   # Azure CNI (pods get VNet IPs)
    network_policy     = "azure"   # enable Azure network policies (or "calico")
    load_balancer_sku  = "standard"
    service_cidr       = "10.0.0.0/16"       
    dns_service_ip     = "10.0.0.10"         
    outbound_type      = "loadBalancer"     
  }

  # Remove private cluster settings
  private_cluster_enabled = false

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  local_account_disabled = true            
  tags = {
    Environment = "Demo"
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix}acr"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                = "Standard"
  admin_enabled      = false    
}

# Grant AKS permission to pull from ACR (AcrPull role)
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
} 
