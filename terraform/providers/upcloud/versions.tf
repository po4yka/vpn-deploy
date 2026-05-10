terraform {
  required_version = ">= 1.15"

  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "~> 5.36"
    }
  }
}
