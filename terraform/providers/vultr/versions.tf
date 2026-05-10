# Stub — fill in for v1.1. See providers/hetzner/README.md for the
# implementation pattern; outputs must match the UpCloud module.

terraform {
  required_version = ">= 1.13"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
  }
}
