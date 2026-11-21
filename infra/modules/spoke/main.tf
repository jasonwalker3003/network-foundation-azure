locals {
  # Carve three /24s out of the /16: .0 web, .1 app, .2 data
  subnets = {
    web  = cidrsubnet(var.address_space, 8, 0)
    app  = cidrsubnet(var.address_space, 8, 1)
    data = cidrsubnet(var.address_space, 8, 2)
  }

  # Inbound rules per subnet. Lower priority numbers are checked first.
  rules = {
    "web-allow-https-internet" = { nsg = "web", priority = 100, access = "Allow", protocol = "Tcp", ports = ["443"], source = "Internet", dest = local.subnets.web, to_app_asg = false }
    "web-deny-vnet"            = { nsg = "web", priority = 4000, access = "Deny", protocol = "*", ports = ["*"], source = "VirtualNetwork", dest = "VirtualNetwork", to_app_asg = false }
    "app-allow-ssh-bastion"    = { nsg = "app", priority = 100, access = "Allow", protocol = "Tcp", ports = ["22"], source = var.bastion_subnet_cidr, dest = null, to_app_asg = true }
    "app-allow-8080-web"       = { nsg = "app", priority = 110, access = "Allow", protocol = "Tcp", ports = ["8080"], source = local.subnets.web, dest = null, to_app_asg = true }
    "app-deny-vnet"            = { nsg = "app", priority = 4000, access = "Deny", protocol = "*", ports = ["*"], source = "VirtualNetwork", dest = "VirtualNetwork", to_app_asg = false }
    "data-allow-app"           = { nsg = "data", priority = 100, access = "Allow", protocol = "Tcp", ports = ["443", "1433"], source = local.subnets.app, dest = local.subnets.data, to_app_asg = false }
    "data-deny-vnet"           = { nsg = "data", priority = 4000, access = "Deny", protocol = "*", ports = ["*"], source = "VirtualNetwork", dest = "VirtualNetwork", to_app_asg = false }
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.prefix}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each                        = local.subnets
  name                            = "snet-${each.key}"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [each.value]
  default_outbound_access_enabled = false # private subnet: no implicit internet access
  # NSG rules only apply to private endpoints when this is Enabled
  private_endpoint_network_policies = each.key == "data" ? "Enabled" : "Disabled"
}

# A label for "app servers": rules target the label, not IP addresses
resource "azurerm_application_security_group" "app" {
  name                = "asg-${var.prefix}-${var.env}-app"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_group" "this" {
  for_each            = local.subnets
  name                = "nsg-${var.prefix}-${var.env}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "this" {
  for_each                                   = local.rules
  name                                       = each.key
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.this[each.value.nsg].name
  priority                                   = each.value.priority
  direction                                  = "Inbound"
  access                                     = each.value.access
  protocol                                   = each.value.protocol
  source_port_range                          = "*"
  source_address_prefix                      = each.value.source
  destination_port_range                     = length(each.value.ports) == 1 ? each.value.ports[0] : null
  destination_port_ranges                    = length(each.value.ports) > 1 ? each.value.ports : null
  destination_address_prefix                 = each.value.to_app_asg ? null : each.value.dest
  destination_application_security_group_ids = each.value.to_app_asg ? [azurerm_application_security_group.app.id] : null
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# Peering is two one-way links; both are needed
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.env}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-${var.env}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}
