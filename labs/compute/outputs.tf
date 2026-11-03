output "lb_ip" {
  value = azurerm_public_ip.pip_lab.ip_address
}

output "app_url" {
  value = "https://${azurerm_linux_web_app.app_lab_sl.default_hostname}"
}
