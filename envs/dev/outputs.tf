output "vm_public_ip" {
  value       = module.vm.public_ip
  description = "Public IP address of the Virtual Machine"
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}
