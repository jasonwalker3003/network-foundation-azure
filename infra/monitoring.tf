# Network Watcher is created per region by Azure; the bootstrap made sure it exists
data "azurerm_network_watcher" "nw" {
  name                = "NetworkWatcher_${local.location}"
  resource_group_name = "NetworkWatcherRG"
}

# Raw flow logs land here as JSON (VNet and storage must be in the same region)
resource "azurerm_storage_account" "flowlogs" {
  name                            = "st${var.prefix}flow"
  resource_group_name             = local.rg
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

# Traffic analytics writes queryable records here
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.2 # cost guard
  tags                = local.tags
}

locals {
  vnets = merge(
    { hub = azurerm_virtual_network.hub.id },
    { for env, s in module.spoke : env => s.vnet_id }
  )
}

# One flow log per VNet: hub, dev, prod
resource "azurerm_network_watcher_flow_log" "vnet" {
  for_each             = local.vnets
  name                 = "fl-${var.prefix}-${each.key}"
  network_watcher_name = data.azurerm_network_watcher.nw.name
  resource_group_name  = data.azurerm_network_watcher.nw.resource_group_name
  location             = data.azurerm_network_watcher.nw.location
  target_resource_id   = each.value
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.logs.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.logs.location
    workspace_resource_id = azurerm_log_analytics_workspace.logs.id
    interval_in_minutes   = 10
  }

  tags = local.tags
}
