---
name: terraform-module-library
description: Terraform conventions for the vpn-deploy multi-provider layout (Hetzner / UpCloud / Vultr). Provider-root strategy, not module composition. Use when adding a provider, editing terraform/providers/**, or wiring inventory rendering. vpn-deploy project variant — does NOT cover AWS/Azure/GCP/OCI patterns from upstream.
---

# Terraform Module Library (vpn-deploy)

This repo uses a **provider-root strategy**, not a module composition strategy. Each cloud
gets its own root under `terraform/providers/<name>/`. The shared cloud-init template lives
under `terraform/shared/`. There are no AWS/Azure/GCP/OCI modules here — discard upstream
examples that reference them.

## Project layout

```
terraform/
  providers/
    hetzner/        # secondary
    upcloud/        # primary
    vultr/          # secondary
  shared/           # cloud-init template, common locals
  CLAUDE.md         # provider-root rationale
```

## Output schema contract

**Every provider root must produce these outputs verbatim.** `scripts/render-inventory.sh`
branches on provider name and reads these keys:

| Output | Type | Notes |
|---|---|---|
| `server_ipv4` | `string` | Public IPv4. Mandatory. |
| `server_ipv6` | `string` | Public IPv6. Empty string if unavailable. |
| `admin_user` | `string` | The user cloud-init created. Usually `admin`. |
| `server_hostname` | `string` | FQDN written into Ansible inventory. |

Adding a new output is fine; renaming or removing one breaks inventory rendering.

## New provider — recipe

From root `CLAUDE.md`:

1. Create `terraform/providers/<name>/` with identical output schema.
2. Add a branch to `scripts/render-inventory.sh` for the new provider's output keys.
3. Add a row to `docs/PROVIDER-NOTES.md` (status, version, known limits).
4. Create `terraform/providers/<name>/CLAUDE.md` (three-section format).

## Hard rules

- **No secrets in `.tfvars`, state, or outputs.** Provider credentials in env vars
  (`HCLOUD_TOKEN`, `UPCLOUD_USERNAME` / `_PASSWORD`, `VULTR_API_KEY`) only.
- **State is local** (or encrypted remote — never plain S3). State files are gitignored.
- **`user_data` is rendered from `terraform/shared/`** — do NOT inline secrets. cloud-init
  only sets admin user, SSH key, python3, and a marker file. Everything else is Ansible.
- **Provider versions pinned** in each provider root's `versions.tf`. Renovate / dependabot
  for upgrades. Pre-releases through staging only.

## Variables — validation discipline

Every input variable needs:

- `type` declared
- `description` non-empty
- `validation { condition = ..., error_message = ... }` for anything with a constrained
  domain (CIDR, region code, instance size)

```hcl
variable "location" {
  description = "UpCloud zone code, e.g. de-fra1"
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]{3}[0-9]$", var.location))
    error_message = "location must match the upcloud zone format (e.g. de-fra1)"
  }
}
```

## Testing

- **`make tf-test`** runs `terraform test` against `mock_provider` blocks. No real cloud
  calls. Every provider root has a `tests/` directory with at least one passing case.
- New provider must include a smoke test that asserts all four output keys are produced.
- Do not run `terraform apply` in CI. Plan-only via `make ci-fast`.

## Don'ts

- **No module composition** between providers. Each root is standalone — operators run
  `terraform -chdir=terraform/providers/upcloud apply`.
- **No remote backends** that store state plaintext.
- **No `null_resource` shelling into Ansible** — that crosses the layer boundary. Ansible
  is invoked by Make, never by Terraform.
- **No DNS record creation** unless wrapped in a separate, optional root. Operators may
  manage DNS out-of-band.

## See also

- `terraform/CLAUDE.md` — provider-root rationale
- `terraform/shared/CLAUDE.md` — cloud-init contract
- `docs/PROVIDER-NOTES.md` — status & quirks per provider
- `[[security-review]]` — what cannot end up in TF state
