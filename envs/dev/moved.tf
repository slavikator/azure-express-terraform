# Address changes from moving resources into modules.
# They can be removed once every state using this code has been applied.

# modules/network
moved {
  from = azurerm_virtual_network.main
  to   = module.network.azurerm_virtual_network.main
}

moved {
  from = azurerm_subnet.main
  to   = module.network.azurerm_subnet.main
}

moved {
  from = azurerm_subnet.mgmt
  to   = module.network.azurerm_subnet.mgmt
}

moved {
  from = azurerm_network_security_group.nsg
  to   = module.network.azurerm_network_security_group.nsg
}

moved {
  from = azurerm_subnet_network_security_group_association.subnet_assoc
  to   = module.network.azurerm_subnet_network_security_group_association.subnet_assoc
}

# modules/vm
moved {
  from = azurerm_public_ip.pip
  to   = module.vm.azurerm_public_ip.pip
}

moved {
  from = azurerm_network_interface.nic
  to   = module.vm.azurerm_network_interface.nic
}

moved {
  from = azurerm_network_interface_security_group_association.nsg_assoc
  to   = module.vm.azurerm_network_interface_security_group_association.nsg_assoc
}

moved {
  from = azurerm_linux_virtual_machine.vm
  to   = module.vm.azurerm_linux_virtual_machine.vm
}
