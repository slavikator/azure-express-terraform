# 1. Resource Group (container for all resources)
resource "azurerm_resource_group" "rg" {
  name     = "rg-devops-demo-swe"
  location = var.location
  tags     = local.tags
}

# 2. Virtual Network (private network)
module "network" {
  source              = "./modules/network"
  name                = "demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

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
