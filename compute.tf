# 1. Приватний реестр контейнерів (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "acrdemodevops${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 2. Середовище Azure Container Apps (Managed Kubernetes під капотом)
resource "azurerm_container_app_environment" "cae" {
  name                = "cae-demo"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# 3. Сам Container App
resource "azurerm_container_app" "app" {
  name                         = "app-express-demo"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    container {
      name   = "express-app"
      image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest" # Початковий базовий образ
      cpu    = 0.25
      memory = "0.5Gi"
    }

    min_replicas = 0
    max_replicas = 2
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 3000

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

