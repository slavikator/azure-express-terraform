# 3. The VM with its public IP, NIC and NIC ↔ NSG association
module "vm" {
  source              = "../../modules/vm"
  name                = "demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
  subnet_id           = module.network.subnet_main_id
  nsg_id              = module.network.nsg_id
  vm_size             = var.vm_size
  ssh_public_key      = var.ssh_public_key
}
