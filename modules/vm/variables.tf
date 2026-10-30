variable "name" {
  description = "Name used to build resource names: pip-<name>-vm, nic-<name>-vm, vm-<name>-node"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}

variable "subnet_id" {
  description = "ID of the subnet the VM's NIC connects to"
  type        = string
}

variable "nsg_id" {
  description = "ID of the NSG attached to the VM's NIC"
  type        = string
}

variable "vm_size" {
  description = "VM size; only burstable B-series sizes are allowed"
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key for the azureuser account"
  type        = string
}
