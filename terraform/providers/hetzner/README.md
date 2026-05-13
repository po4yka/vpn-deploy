# Hetzner provider

Terraform root for a single Hetzner Cloud VPS running the provider-neutral
Ansible stack.

Credentials come from `HCLOUD_TOKEN`; do not place provider tokens in tfvars.
The root exports the same inventory-facing outputs as `providers/upcloud/`:

- `server_ipv4`
- `server_ipv6`
- `honeypot_ipv4`
- `admin_user`
- `server_hostname`
- `zone`

Example:

```bash
cp terraform/providers/hetzner/environments/prod.tfvars.example \
   terraform/providers/hetzner/environments/prod.tfvars
$EDITOR terraform/providers/hetzner/environments/prod.tfvars
HCLOUD_TOKEN=... make PROVIDER=hetzner ENV=prod init plan
```
