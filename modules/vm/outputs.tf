output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_linux_virtual_machine.vm.public_ip_address
}

output "vm_id" {
  description = "ID of the VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "principal_id" {
  description = "Principal ID"
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}
