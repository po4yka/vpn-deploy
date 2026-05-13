# Terraform layer

Each provider lives in its own root module under `providers/<name>/`. They
share `shared/cloud-init.yaml.tftpl` for the bootstrap template.

Use Terraform >= 1.15. Each provider root commits its own
`.terraform.lock.hcl` so CI and operator workstations resolve the same provider
builds.

## Why per-provider root modules

Terraform requires every `module "x" { source = "…" }` to use a static
path; you cannot pick a provider through a variable. Per-provider roots
give you a clean drop-in: the operator runs `make PROVIDER=upcloud …` (or
`hetzner`, `vultr`), and the Makefile `cd`s into the right directory.

## Switching providers

```bash
make PROVIDER=upcloud   init plan apply
make PROVIDER=hetzner   init plan apply
make PROVIDER=vultr     init plan apply
```

The Ansible layer is provider-neutral — only the inventory render script
reads provider-specific Terraform outputs.

## State

State is local by default (`*.tfstate` next to the root module, in
`.gitignore`). Back it up out-of-band; without state Terraform cannot
follow blue-green or rotate the floating IP. See
`docs/RUNBOOK-incident.md` § "State loss".

## Providers

| Provider | Status | Notes |
|---|---|---|
| `upcloud` | primary (v1) | Uses `UpCloudLtd/upcloud`. Region `fi-hel1` recommended for EU baseline. |
| `hetzner` | implemented (v1.1) | Uses `hetznercloud/hcloud`. Export `HCLOUD_TOKEN` before planning. |
| `vultr`   | implemented (v1.1) | Uses `vultr/vultr`. Export `TF_VAR_vultr_api_key` before planning. |
