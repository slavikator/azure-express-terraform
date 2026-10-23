variable "ssh_public_key" {
  type        = string
  description = "Public SSH key for VM authentication"
}

variable "location" {
  type    = string
  default = "swedencentral"

  validation {
    condition     = contains(["swedencentral", "northeurope"], var.location)
    error_message = "Only swedencentral or northeurope allowed!"
  }
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ls_v2"
}

variable "nsg_rules" {
  description = "Inbound NSG rules: name => priority and port"
  type        = map(object({ priority = number, port = string }))
  default = {
    SSH   = { priority = 1001, port = "22" }
    HTTP  = { priority = 1002, port = "80" }
  }
}
