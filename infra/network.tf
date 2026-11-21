data "azurerm_resource_group" "main" {
  name = "rg-${var.prefix}"
}

locals {
  rg           = data.azurerm_resource_group.main.name
  location     = data.azurerm_resource_group.main.location
  tags         = { project = "network-foundation", owner = "jason", env = "lab" }
  hub_cidr     = "10.10.0.0/16"
  bastion_cidr = "10.10.0.0/26"
  spokes = {
    dev  = "10.20.0.0/16"
    prod = "10.30.0.0/16"
  }
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub"
  resource_group_name = local.rg
  location            = local.location
  address_space       = [local.hub_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet" # Azure requires exactly this name
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.bastion_cidr]
}

resource "azurerm_subnet" "management" {
  name                            = "snet-management"
  resource_group_name             = local.rg
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = ["10.10.1.0/24"]
  default_outbound_access_enabled = false
}

module "spoke" {
  source   = "./modules/spoke"
  for_each = local.spokes

  env                 = each.key
  prefix              = var.prefix
  location            = local.location
  resource_group_name = local.rg
  address_space       = each.value
  hub_vnet_id         = azurerm_virtual_network.hub.id
  hub_vnet_name       = azurerm_virtual_network.hub.name
  bastion_subnet_cidr = local.bastion_cidr
  tags                = local.tags
}
