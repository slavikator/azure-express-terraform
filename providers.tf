terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.118.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  backend "azurerm" {
    # ваші параметри бекенду залишаються без змін
  }
}

provider "azurerm" {
  features {}
}

