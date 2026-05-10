# Stub — fill in for v1.1.
#
# When implementing:
#   - Replicate variables.tf / main.tf / firewall.tf / outputs.tf shape
#     from providers/upcloud/.
#   - Use hcloud_server, hcloud_firewall, hcloud_firewall_attachment,
#     hcloud_ssh_key.
#   - Pass user_data via templatefile() against ../../shared/cloud-init.yaml.tftpl
#     identical to the UpCloud module.
#   - outputs must match the UpCloud module name-for-name so
#     scripts/render-inventory.sh works without changes.

terraform {
  required_version = ">= 1.15"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.62"
    }
  }
}
