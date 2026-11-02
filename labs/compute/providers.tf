terraform {
  required_version = ">=1.8.0"
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
    key                  = "lab-compute.terraform.tfstate"
  }

}

provider "azurerm" {
  features {}
}
