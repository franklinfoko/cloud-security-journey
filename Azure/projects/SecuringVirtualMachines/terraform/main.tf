terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.53.0"
    }
  }
}

provider "azurerm" {
    features {}
    subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "this" {
  name     = "RG_Web_Server"
  location = "canadacentral"
}

resource "azurerm_resource_group" "this2" {
  name     = "Firewall"
  location = "canadacentral"
}

resource "azurerm_virtual_network" "this" {
  name = "Web_Server"
  location = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space = ["10.0.0.0/16"]
}

resource "azurerm_virtual_network" "this2" {
  name = "Firewall-Hub"
  location = azurerm_resource_group.this2.location
  resource_group_name = azurerm_resource_group.this2.name
  address_space = ["192.168.0.0/16"]
}

resource "azurerm_subnet" "this" {
  name                 = "Web_Server_subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "this2" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this2.name
  virtual_network_name = azurerm_virtual_network.this2.name
  address_prefixes     = ["192.168.1.0/24"]
}

resource "azurerm_windows_virtual_machine" "this" {
  name                = "SamScoopsWeb"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_F2"
  admin_username      = "AzAdmin"
  admin_password      = "P@$$@1234567"
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "this" {
  name                = "SamScoopsWeb-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

resource "azurerm_public_ip" "this" {
  name                = "SamScoopsWeb-pi"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"

  tags = {
    environment = "Test"
  }
}

resource "azurerm_public_ip" "this2" {
  name                = "FirewallScoops"
  resource_group_name = azurerm_resource_group.this2.name
  location            = azurerm_resource_group.this2.location
  allocation_method   = "Static"

  tags = {
    environment = "Test"
  }
}

resource "azurerm_network_security_group" "this" {
  name                = "SamScoopsWeb-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "testInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Test"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# VNET Peering
resource "azurerm_virtual_network_peering" "this" {
  name                      = "Hub-Web"
  resource_group_name       = azurerm_resource_group.this2.name
  virtual_network_name      = azurerm_virtual_network.this2.name
  remote_virtual_network_id = azurerm_virtual_network.this.id
}
resource "azurerm_virtual_network_peering" "this2" {
  name                      = "spoke-Web"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = azurerm_virtual_network.this2.id
}

# Firewall
resource "azurerm_firewall" "this" {
  name                = "ScoopsFirewall"
  location            = azurerm_resource_group.this2.location
  resource_group_name = azurerm_resource_group.this2.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.this2.id
    public_ip_address_id = azurerm_public_ip.this2.id
  }

  threat_intel_mode = "Deny"
}

resource "azurerm_firewall_application_rule_collection" "this" {
  name                = "AppRule1"
  azure_firewall_name = azurerm_firewall.this.name
  resource_group_name = azurerm_resource_group.this2.name
  priority            = 200
  action              = "Allow"

  rule {
    name = "Allow-Google"

    source_addresses = [
      "10.0.1.0/24",
    ]

    target_fqdns = [
      "www.google.com",
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "this" {
  name                = "Net-Rule1"
  azure_firewall_name = azurerm_firewall.this.name
  resource_group_name = azurerm_resource_group.this2.name
  priority            = 200
  action              = "Allow"

  rule {
    name = "Allow-DNS"

    source_addresses = [
      "10.0.1.0/24",
    ]

    destination_ports = [
      "53",
    ]

    destination_addresses = [
      "209.244.0.3",
      "209.244.0.4",
    ]

    protocols = [
      "UDP",
    ]
  }
}

resource "azurerm_firewall_nat_rule_collection" "this" {
  name                = "rdp"
  azure_firewall_name = azurerm_firewall.this.name
  resource_group_name = azurerm_resource_group.this2.name
  priority            = 200
  action              = "Dnat"

  rule {
    name = "rdp-nat"

    source_addresses = [
      "10.0.0.0/16",
    ]

    destination_ports = [
      "53",
    ]

    destination_addresses = [
      azurerm_public_ip.this2.ip_address
    ]

    translated_port = 3389

    translated_address = "10.0.1.4"

    protocols = [
      "TCP"
    ]
  }
}

# Azure bastion
resource "azurerm_subnet" "this3" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "this3" {
  name                = "bastionIp"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  name                = "bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.this3.id
    public_ip_address_id = azurerm_public_ip.this3.id
  }
}