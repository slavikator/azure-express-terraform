# 1. Ubuntu virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                              = "vm-demo-node"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  size                              = var.vm_size
  admin_username                    = "azureuser"
  vm_agent_platform_updates_enabled = false
  tags                              = local.tags

  custom_data = base64encode(<<-EOF
              #!/bin/bash
              # 1. Install Docker
              apt-get update
              apt-get install -y docker.io docker-compose
              systemctl enable --now docker
              usermod -aG docker azureuser

              # 2. Create a folder for the Express app
              mkdir -p /home/azureuser/app
              cd /home/azureuser/app

              # 3. Write the Express server code
              cat << 'APP_EOF' > server.js
              const express = require('express');
              const app = express();
              const PORT = 3000;

              app.get('/', (req, res) => {
                res.json({
                  status: "success",
                  message: "🚀 Test2! Hello from Express v2.0.0 updated via GitHub Actions CI/CD Pipeline!",
                  timestamp: new Date()
                });
              });

              app.listen(PORT, () => console.log(`Server running on port $${PORT}`));
              APP_EOF

              # 4. Write package.json
              cat << 'PKG_EOF' > package.json
              {
                "name": "express-demo",
                "version": "1.0.0",
                "main": "server.js",
                "dependencies": { "express": "^4.18.2" }
              }
              PKG_EOF

              # 5. Write the Dockerfile
              cat << 'DOCKER_EOF' > Dockerfile
              FROM node:18-alpine
              WORKDIR /app
              COPY package*.json ./
              RUN npm install
              COPY . .
              EXPOSE 3000
              CMD ["node", "server.js"]
              DOCKER_EOF

              # 6. Build and run the Docker container on port 80
              docker build -t express-app:v1 .
              docker run -d -p 80:3000 --name my-express-app --restart always express-app:v1
              EOF
  )

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

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
  lifecycle {
    ignore_changes = [
      vm_agent_platform_updates_enabled,
      custom_data,
    ]
  }
}
