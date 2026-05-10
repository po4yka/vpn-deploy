# Terraform layer

Each provider lives in its own root module under `providers/<name>/`. They
share `shared/cloud-init.yaml.tftpl` for the bootstrap template.

## Why per-provider root modules

Terraform requires every `module "x" { source = "…" }` to use a static
path; you cannot pick a provider through a variable. Per-provider roots
give you a clean drop-in: the operator runs `make PROVIDER=upcloud …` (or
`hetzner`, `vultr` once those stubs are filled in), and the Makefile
`cd`s into the right directory.

## Switching providers

```bash
make PROVIDER=upcloud   init plan apply
make PROVIDER=hetzner   init plan apply   # once stub is implemented
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
| `hetzner` | stub | Pin `hetznercloud/hcloud`. |
| `vultr`   | stub | Pin `vultr/vultr`. |
