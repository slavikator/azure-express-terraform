# 1. Resource Group (container for all resources)
resource "azurerm_resource_group" "rg" {
  name     = "rg-devops-demo-swe"
  location = var.location
  tags     = local.tags
}

# 2. Network: VNet, subnets, NSG and NSG ↔ subnet association
module "network" {
  source              = "../../modules/network"
  name                = "demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
  nsg_rules           = var.nsg_rules
}
