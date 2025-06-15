terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"    # Use a recent version of the Azure provider
    }
  }
}

provider "azurerm" {
  features {}               # Enable all AZ resources (no special features needed)
} 