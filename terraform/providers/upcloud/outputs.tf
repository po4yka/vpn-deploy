output "server_ipv4" {
  value       = [for ni in upcloud_server.vpn.network_interface : ni.ip_address if ni.type == "public" && ni.ip_address_family == "IPv4"][0]
  description = "Public IPv4 address."
}

output "server_ipv6" {
  value       = try([for ni in upcloud_server.vpn.network_interface : ni.ip_address if ni.type == "public" && ni.ip_address_family == "IPv6"][0], null)
  description = "Public IPv6 address (may be null if disabled)."
}

output "admin_user" {
  value = var.admin_user
}

output "server_hostname" {
  value = upcloud_server.vpn.hostname
}

output "zone" {
  value = upcloud_server.vpn.zone
}

# Do NOT output:
#   - REALITY private keys
#   - VLESS UUIDs / shortIds
#   - Hysteria passwords
#   - subscription tokens
# These never leave the SOPS-encrypted secrets file.
