# Copyright 2019 Google LLC All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.94.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "client_id" {}
variable "client_secret" {}
variable "cluster_name" {
  default = "test-cluster"
}
variable "resource_group_location" {
  default = "northeurope"
}
variable "resource_group_name" {
  default = "agonesRG"
}
variable "kubernetes_version" {
  default = "1.27.1" # Replace with a supported Kubernetes version
}
variable "machine_type" {
  default = "Standard_D2_v2"
}
variable "node_count" {
  default = 4
}
variable "disk_size" {
  default = 30
}
variable "enable_node_public_ip" {
  default = false
}

# Resource group for AKS
resource "azurerm_resource_group" "agones" {
  location = var.resource_group_location
  name     = var.resource_group_name
}

# AKS cluster definition
resource "azurerm_kubernetes_cluster" "agones" {
  name                = var.cluster_name
  location            = azurerm_resource_group.agones.location
  resource_group_name = azurerm_resource_group.agones.name
  dns_prefix          = "agones"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.machine_type
    os_disk_size_gb = var.disk_size
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

# Additional node pool for system workloads
resource "azurerm_kubernetes_cluster_node_pool" "system" {
  name                  = "system"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.agones.id
  vm_size               = var.machine_type
  node_count            = 1
  os_disk_size_gb       = var.disk_size
  enable_auto_scaling   = false
  node_taints           = ["agones.dev/agones-system=true:NoExecute"]
  node_labels = {
    "agones.dev/agones-system" = "true"
  }
}

# Additional node pool for metrics workloads
resource "azurerm_kubernetes_cluster_node_pool" "metrics" {
  name                  = "metrics"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.agones.id
  vm_size               = var.machine_type
  node_count            = 1
  os_disk_size_gb       = var.disk_size
  enable_auto_scaling   = false
  node_taints           = ["agones.dev/agones-metrics=true:NoExecute"]
  node_labels = {
    "agones.dev/agones-metrics" = "true"
  }
}

# Network security rule for game server
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
  resource_group_name        = azurerm_resource_group.agones.name
  network_security_group_name = "aks-agentpool-55978144-nsg"

  depends_on = [
    azurerm_kubernetes_cluster.agones,
    azurerm_kubernetes_cluster_node_pool.system,
    azurerm_kubernetes_cluster_node_pool.metrics
  ]
}
