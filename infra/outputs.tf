output "test_vm_ips" {
  value = { for name, v in local.test_vms : name => v.ip }
}
output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}
output "private_endpoint_ip" {
  value = var.enable_private_endpoint ? azurerm_private_endpoint.kv[0].private_service_connection[0].private_ip_address : null
}
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.logs.workspace_id
}
