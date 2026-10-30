output "vnet_name" { value = azurerm_virtual_network.main.name }
output "vnet_id" { value = azurerm_virtual_network.main.id }
output "subnet_main_id" {
  value = azurerm_subnet.main.id
}
