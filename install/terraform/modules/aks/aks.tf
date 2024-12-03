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

# Define Variables or use a variables.tf file
variable "resource_group_location" {
  description = "The Azure location where the resource group will be created."
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  default     = "agones-rg"
}

variable "cluster_name" {
  description = "The name of the AKS cluster."
  type        = string
  default     = "agones-aks"
}

variable "kubernetes_version" {
  description = "The Kubernetes version."
  type        = string
  default     = "1.25.4"
}

variable "node_count" {
  description = "Number of nodes in the default node pool."
  type        = number
  default     = 3
}

variable "machine_type" {
  description = "The VM size for the nodes."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "disk_size" {
  description = "OS disk size in GB."
  type        = number
  default     = 30
}

variable "enable_node_public_ip" {
  description = "Whether to assign public IPs to nodes."
  type        = bool
  default     = false
}

variable "client_id" {
  description = "Service Principal Client ID."
  type        = string
}

variable "client_secret" {
  description = "Service Principal Client Secret."
  type        = string
  sensitive   = true
}

module "aks_cluster" {
  source = "git::https://github.com/ltwlf/agones.git?ref=main"  # Update the source as needed

  resource_group_location = var.resource_group_location
  resource_group_name     = var.resource_group_name
  cluster_name            = var.cluster_name
  kubernetes_version      = var.kubernetes_version
  node_count              = var.node_count
  machine_type            = var.machine_type
  disk_size               = var.disk_size
  enable_node_public_ip   = var.enable_node_public_ip
  client_id               = var.client_id
  client_secret           = var.client_secret

  providers = {
    azurerm = azurerm
  }
}

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
  resource_group_name        = module.aks_cluster.node_resource_group

  # NSG Name based on hashed dns_prefix
  network_security_group_name = "aks-agentpool-55978144-nsg"

  depends_on = [
    module.aks_cluster,
  ]

  # Ignore changes to resource_group_name due to case sensitivity issues
  lifecycle {
    ignore_changes = [
      resource_group_name
    ]
  }
}
