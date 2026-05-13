terraform {
  required_version = ">= 1.15"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.31"
    }
  }
}
