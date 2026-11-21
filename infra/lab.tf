data "azurerm_client_config" "current" {}

# ---------- Always on (free when idle) ----------

# Locked to private access only: the internet can't reach it at all
resource "azurerm_key_vault" "kv" {
  name                          = "kv-${var.prefix}-lab"
  resource_group_name           = local.rg
  location                      = local.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = false
  tags                          = local.tags
}

# Private DNS: inside the VNets, the vault's name resolves to its private IP
resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.rg
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  for_each              = local.vnets
  name                  = "link-${each.key}"
  resource_group_name   = local.rg
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = local.tags
}

# ---------- Switch: private endpoint ----------

resource "azurerm_private_endpoint" "kv" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${var.prefix}-kv"
  resource_group_name = local.rg
  location            = local.location
  subnet_id           = module.spoke["dev"].subnet_ids["data"]

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
  tags = local.tags
}

# ---------- Switch: test VMs ----------
# dev-app and prod-app prove isolation; dev-web lets you test the NSG between two tiers

locals {
  test_vm_defs = {
    "dev-app"  = { env = "dev", tier = "app" }  # 10.20.1.10
    "dev-web"  = { env = "dev", tier = "web" }  # 10.20.0.10
    "prod-app" = { env = "prod", tier = "app" } # 10.30.1.10
  }
  test_vms = var.enable_test_vms ? {
    for name, d in local.test_vm_defs : name => {
      tier      = d.tier
      subnet_id = module.spoke[d.env].subnet_ids[d.tier]
      ip        = cidrhost(module.spoke[d.env].subnet_cidrs[d.tier], 10)
      asg_id    = module.spoke[d.env].app_asg_id
    }
  } : {}
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.test_vms
  name                = "nic-${var.prefix}-${each.key}"
  resource_group_name = local.rg
  location            = local.location
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
  tags = local.tags
}

# Put app-tier VMs in their spoke's "app servers" group, so the app NSG rules apply
resource "azurerm_network_interface_application_security_group_association" "vm" {
  for_each                      = { for name, v in local.test_vms : name => v if v.tier == "app" }
  network_interface_id          = azurerm_network_interface.vm[each.key].id
  application_security_group_id = each.value.asg_id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each              = local.test_vms
  name                  = "vm-${var.prefix}-${each.key}"
  resource_group_name   = local.rg
  location              = local.location
  size                  = "Standard_B1s"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.vm[each.key].id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("${path.module}/keys/p3lab.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {} # managed storage; lets you use the serial console if SSH fails
  tags = local.tags
}

# ---------- Switch: Bastion (the most expensive part) ----------

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-${var.prefix}-bastion"
  resource_group_name = local.rg
  location            = local.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_bastion_host" "hub" {
  count               = var.enable_bastion ? 1 : 0
  name                = "bas-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "Basic"
  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
  tags = local.tags
}
