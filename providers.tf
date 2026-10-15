terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate1791293035"
    container_name       = "tfstate"
    key                  = "demo-node.terraform.tfstate"
  }

}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}
