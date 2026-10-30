variable "name" { type = string }
variable "address_space" { type = list(string) }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }
variable "nsg_rules" {
  description = "Inbound NSG rules: name => priority and port"
  type        = map(object({ priority = number, port = string }))
}
