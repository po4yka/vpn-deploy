# Hetzner provider — stub

Not implemented in v1. The shape mirrors `providers/upcloud/`:

- `variables.tf` — same vars (server_name, admin_*, allowed_ssh_cidrs, enable_hysteria, labels) plus Hetzner-specific (location, server_type, image).
- `main.tf` — `hcloud_ssh_key` + `hcloud_server` with `user_data` from `../../shared/cloud-init.yaml.tftpl`.
- `firewall.tf` — `hcloud_firewall` with the same port/CIDR shape (22 restricted, 443/tcp open, 443/udp conditional).
- `outputs.tf` — must export `server_ipv4`, `server_ipv6`, `admin_user`, `server_hostname` to stay compatible with `scripts/render-inventory.sh`.

To implement:

```bash
git mv terraform/providers/upcloud terraform/providers/upcloud  # for diffing
# write hcloud-equivalent main.tf / firewall.tf / variables.tf / outputs.tf
make PROVIDER=hetzner ENV=staging init plan
```
