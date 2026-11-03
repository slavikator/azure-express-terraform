resource "azurerm_log_analytics_workspace" "log_lab" {
  name                = "log-lab"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "diag_app_lab" {
  name                       = "diag-app-lab"
  target_resource_id         = azurerm_linux_web_app.app_lab_sl.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_lab.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
}

resource "azurerm_monitor_action_group" "ag_lab" {
  name                = "ag-lab"
  resource_group_name = azurerm_resource_group.rg_lab.name
  short_name          = "aglab"

  email_receiver {
    name          = "SL"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "alert_cpu_lab" {
  name                = "alert-cpu-lab"
  resource_group_name = azurerm_resource_group.rg_lab.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.vmss_lab.id]
  description         = "VMSS CPU above 80%"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  action {
    action_group_id = azurerm_monitor_action_group.ag_lab.id
  }
}
