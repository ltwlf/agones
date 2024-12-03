# ------------------------------------------------------------------------------
# Terraform Configuration for Agones on Azure Kubernetes Service (AKS)
# Updated to use the latest AzureRM provider while retaining Service Principal.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"  # Updated to the latest major version
    }
  }
}

provider "azurerm" {
  features {}
}

# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "agones" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

# ------------------------------------------------------------------------------
# Azure Kubernetes Service (AKS) Cluster
# ------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "agones" {
  name                = var.cluster_name
  location            = azurerm_resource_group.agones.location
  resource_group_name = azurerm_resource_group.agones.name
  dns_prefix          = "agones"  # Do not change to ensure consistent NSG naming

  kubernetes_version = var.kubernetes_version

  # Service Principal Configuration
  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }

  # Default Node Pool Configuration
  default_node_pool {
    name                  = "default"
    node_count            = var.node_count
    vm_size               = var.machine_type
    os_disk_size_gb       = var.disk_size
    enable_auto_scaling   = false
    enable_node_public_ip = var.enable_node_public_ip

    # Tags specific to the node pool (optional)
    tags = {
      "nodepool-type" = "default"
    }
  }

  tags = {
    Environment = "Production"
  }
}

# ------------------------------------------------------------------------------
# System Node Pool
# ------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "system" {
  name                  = "system"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.agones.id
  vm_size               = var.machine_type
  node_count            = 1
  os_disk_size_gb       = var.disk_size
  enable_auto_scaling   = false

  # Taints to isolate system nodes
  node_taints = [
    "agones.dev/agones-system=true:NoExecute"
  ]

  # Labels for system nodes
  node_labels = {
    "agones.dev/agones-system" = "true"
  }

  # Ensure system node pool is created after the main AKS cluster
  depends_on = [
    azurerm_kubernetes_cluster.agones
  ]
}

# ------------------------------------------------------------------------------
# Metrics Node Pool
# ------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "metrics" {
  name                  = "metrics"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.agones.id
  vm_size               = var.machine_type
  node_count            = 1
  os_disk_size_gb       = var.disk_size
  enable_auto_scaling   = false

  # Taints to isolate metrics nodes
  node_taints = [
    "agones.dev/agones-metrics=true:NoExecute"
  ]

  # Labels for metrics nodes
  node_labels = {
    "agones.dev/agones-metrics" = "true"
  }

  # Ensure metrics node pool is created after the main AKS cluster
  depends_on = [
    azurerm_kubernetes_cluster.agones
  ]
}

# ------------------------------------------------------------------------------
# Network Security Rule for Game Servers
# ------------------------------------------------------------------------------

resource "azurerm_network_security_rule" "gameserver" {
  name                       = "gameserver"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Udp"
  source_port_range          = "*"
  destination_port_range     = "7000-8000"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  resource_group_name        = azurerm_kubernetes_cluster.agones.node_resource_group

  # NSG Name based on hashed dns_prefix
  network_security_group_name = "aks-agentpool-55978144-nsg"

  depends_on = [
    azurerm_kubernetes_cluster.agones,
    azurerm_kubernetes_cluster_node_pool.metrics,
    azurerm_kubernetes_cluster_node_pool.system
  ]

  # Ignore changes to resource_group_name due to case sensitivity issues
  lifecycle {
    ignore_changes = [
      resource_group_name
    ]
  }
}
