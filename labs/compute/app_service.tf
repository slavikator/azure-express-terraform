resource "azurerm_service_plan" "asp_lab" {
  name                = "asp-lab"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
  os_type             = "Linux"
  sku_name            = "B1"
}

# tflint-ignore: azurerm_app_service_missing_auto_heal_setting # lab only
resource "azurerm_linux_web_app" "app_lab_sl" {
  name                = "app-lab-sl"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
  service_plan_id     = azurerm_service_plan.asp_lab.id

  site_config {
    application_stack {
      docker_image_name   = "nginxdemos/hello:latest"
      docker_registry_url = "https://index.docker.io"
    }
  }
}
