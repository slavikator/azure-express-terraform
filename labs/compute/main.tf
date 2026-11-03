resource "azurerm_resource_group" "rg_lab" {
  name     = "rg-lab-compute-swe"
  location = "swedencentral"
}

resource "azurerm_virtual_network" "vnet_lab" {
  name                = "vnet-lab"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
}

resource "azurerm_subnet" "main" {
  name                 = "snet-internal"
  resource_group_name  = azurerm_resource_group.rg_lab.name
  virtual_network_name = azurerm_virtual_network.vnet_lab.name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.vnet_lab.address_space[0], 8, 1)]
}

resource "azurerm_public_ip" "pip_lab" {
  name                = "pip-lab"
  sku                 = "Standard"
  allocation_method   = "Static"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
}

resource "azurerm_lb" "lb_lab" {
  name                = "lb-lab"
  sku                 = "Standard"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.pip_lab.id
  }
}

resource "azurerm_lb_backend_address_pool" "pool_lab" {
  name            = "pool-lab"
  loadbalancer_id = azurerm_lb.lb_lab.id
}

resource "azurerm_lb_probe" "probe_lab" {
  name            = "probe-lab"
  loadbalancer_id = azurerm_lb.lb_lab.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

resource "azurerm_lb_rule" "rule_lab" {
  name                     = "rule-lab"
  loadbalancer_id          = azurerm_lb.lb_lab.id
  protocol                 = "Tcp"
  frontend_port            = 80
  backend_port             = 80
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.pool_lab.id]
  probe_id                 = azurerm_lb_probe.probe_lab.id

  frontend_ip_configuration_name = "frontend"
}

resource "azurerm_network_security_group" "nsg_lab" {
  name                = "nsg-lab"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name

  security_rule {
    name                       = "Http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_monitor_autoscale_setting" "autoscale_lab" {
  name                = "autoscale-lab"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss_lab.id

  profile {
    name = "default"

    capacity {
      minimum = 1
      default = 1
      maximum = 2
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss_lab.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss_lab.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss_lab" {
  name                = "vmss-lab"
  location            = azurerm_resource_group.rg_lab.location
  resource_group_name = azurerm_resource_group.rg_lab.name
  sku                 = "Standard_B2ls_v2"
  instances           = 1
  upgrade_mode        = "Manual"
  admin_username      = "azureuser"

  lifecycle {
    ignore_changes = [instances]
  }

  custom_data = base64encode(<<-EOF
  #cloud-config
  runcmd:
    - mkdir -p /srv/www
    - echo "Hello from $(hostname)" > /srv/www/index.html
    - nohup python3 -m http.server 80 --directory /srv/www > /dev/null 2>&1 &
  EOF
  )

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  network_interface {
    name                      = "nic-lab"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.nsg_lab.id

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.main.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.pool_lab.id]
    }
  }
}
