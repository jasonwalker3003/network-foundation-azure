output "vnet_id" {
  value = azurerm_virtual_network.this.id
}
output "vnet_name" {
  value = azurerm_virtual_network.this.name
}
output "subnet_ids" {
  value = { for k, s in azurerm_subnet.this : k => s.id }
}
output "subnet_cidrs" {
  value = local.subnets
}
output "app_asg_id" {
  value = azurerm_application_security_group.app.id
}
