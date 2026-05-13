# Vultr provider

Terraform root for a single Vultr VPS running the provider-neutral Ansible
stack.

The Vultr provider requires `api_key` in the Terraform provider config. This
root wires it through the sensitive `vultr_api_key` variable; prefer exporting
`TF_VAR_vultr_api_key` instead of writing tokens into tfvars.

The root exports the same inventory-facing outputs as `providers/upcloud/`:

- `server_ipv4`
- `server_ipv6`
- `honeypot_ipv4`
- `admin_user`
- `server_hostname`
- `zone`

Example:

```bash
cp terraform/providers/vultr/environments/prod.tfvars.example \
   terraform/providers/vultr/environments/prod.tfvars
$EDITOR terraform/providers/vultr/environments/prod.tfvars
TF_VAR_vultr_api_key=... make PROVIDER=vultr ENV=prod init plan
```
