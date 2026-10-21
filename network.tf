# 1. Resource Group (container for all resources)
resource "azurerm_resource_group" "rg" {
  name     = "rg-devops-demo-swe"
  location = var.location
  tags     = local.tags
}

# 2. Virtual Network (private network)
resource "azurerm_virtual_network" "main" {
  name                = "vnet-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# 3. Subnet (subnet for our VM)
resource "azurerm_subnet" "main" {
  name                 = "snet-internal"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.main.address_space[0], 8, 1)]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.main.address_space[0], 8, 2)]
}

moved {
  from = azurerm_subnet.subnet
  to   = azurerm_subnet.main
}
