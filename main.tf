terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "Dev-RG" {
  name     = "${var.RG-Name}"
  location = "${var.RG-Location}"
  tags = {
    Environment = "Dev"
  }
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "Dev-VN" {
  name                = "Dev-network"
  resource_group_name = azurerm_resource_group.Dev-RG.name
  location            = azurerm_resource_group.Dev-RG.location
  address_space       = ["10.0.0.0/16"]
  tags = {
    Environment = "Dev"
  }
}

resource "azurerm_subnet" "Dev-Subnet" {
  name                 = "Dev-Subnet"
  resource_group_name  = azurerm_resource_group.Dev-RG.name
  virtual_network_name = azurerm_virtual_network.Dev-VN.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "Dev-SGP" {
  name                = "Dev-SGP"
  location            = azurerm_resource_group.Dev-RG.location
  resource_group_name = azurerm_resource_group.Dev-RG.name

  tags = {
    Environment = "Dev"
  }

}

resource "azurerm_network_security_rule" "Dev-SGP-Rule" {
  name                        = "Dev-SGP-Rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.Dev-RG.name
  network_security_group_name = azurerm_network_security_group.Dev-SGP.name
}

resource "azurerm_subnet_network_security_group_association" "Dev-Sub-Group-association" {
  subnet_id                 = azurerm_subnet.Dev-Subnet.id
  network_security_group_id = azurerm_network_security_group.Dev-SGP.id
}

resource "azurerm_public_ip" "Dev-ip" {
  name                = "Dev-ip"
  resource_group_name = azurerm_resource_group.Dev-RG.name
  location            = azurerm_resource_group.Dev-RG.location
  allocation_method   = "Dynamic"

  tags = {
    Environment = "Dev"
  }
}

resource "azurerm_network_interface" "Dev-NIC" {
  name                = "Dev-NIC"
  location            = azurerm_resource_group.Dev-RG.location
  resource_group_name = azurerm_resource_group.Dev-RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.Dev-Subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.Dev-ip.id
  }

  tags = {
    Environment = "Dev"
  }
}

resource "azurerm_linux_virtual_machine" "Dev-VM" {
  name                = "Dev-VM"
  resource_group_name = azurerm_resource_group.Dev-RG.name
  location            = azurerm_resource_group.Dev-RG.location
  size                = "Standard_D2s_v3"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.Dev-NIC.id,
  ]

  custom_data = filebase64("customdata.tpl")
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/Dev-Azure-Key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

provisioner "local-exec" {
   command = templatefile("${var.host_os}-ssh-script.tpl", {
    hostname = self.public_ip_address,
    user = "adminuser",
    identityfile = "~/.ssh/Dev-Azure-Key"
   })
   interpreter = [
     "Powershell", "-Command"
   ]
}
  tags = {
    Environment = "Dev"
  }
}

data "azurerm_public_ip" "Dev-ip-data"{
  name = azurerm_public_ip.Dev-ip.name
  resource_group_name = azurerm_resource_group.Dev-RG.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.Dev-VM.name}: ${data.azurerm_public_ip.Dev-ip-data.ip_address}"
}