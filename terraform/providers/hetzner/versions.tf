terraform {
  required_version = ">= 1.15"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.62"
    }
  }
}
