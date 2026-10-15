output "vm_public_ip" {
  value       = azurerm_linux_virtual_machine.vm.public_ip_address
  description = "Public IP address of the Virtual Machine"
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}
