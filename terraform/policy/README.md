# terraform/policy — Conftest / OPA policies

Cross-provider policy layer above the per-provider `terraform test` suite.
Every provider plan must satisfy all rules before merge.

## Policies

| File | Rule | Deny condition |
|---|---|---|
| `server_metadata.rego` | `every_server_has_metadata_enabled` | Any `upcloud_server`, `hcloud_server`, or `vultr_instance` resource has `metadata = false` in the post-apply state. |
| `secondary_ip.rego` | `no_secondary_public_ip_without_opt_in` | A server plan adds more than one public network interface (or a companion `hcloud_floating_ip` / `vultr_instance_ipv4` resource) without `var.additional_public_ip = true`. |
| `admin_port.rego` | `no_admin_port_exposed_to_world` | Any firewall resource allows TCP/22, TCP/3389, or `var.panel_port` from `0.0.0.0/0` or `::/0`. |
| `ssh_cidrs.rego` | `firewall_rules_pin_ssh_to_documented_cidrs` | An SSH allow rule (TCP/22) references a source CIDR not present in `var.allowed_ssh_cidrs`. |
| `no_secrets_in_user_data.rego` | `cloud_init_user_data_contains_no_secrets` | A server resource's `user_data` (cloud-init) contains a plaintext string matching `(secret\|password\|token\|key)\s*[:=]\s*[^\s]{6,}`. |

Fail-on-violation only — no `--warn` flag is passed (Open Question 6 resolution).

## Running locally

```sh
# 1. Generate the plan JSON for a provider
terraform -chdir=terraform/providers/upcloud init -backend=false
terraform -chdir=terraform/providers/upcloud plan \
  -out=plan.bin \
  -var-file=environments/prod.tfvars.example
terraform -chdir=terraform/providers/upcloud show -json plan.bin > plan.json

# 2. Run conftest against all policies
conftest test -p terraform/policy/ plan.json
```

Repeat with `hetzner` and `vultr` as the `-chdir` target.

## Make target

```sh
make tf-policy
```

Iterates over all three providers automatically (requires `terraform` and
`conftest` on `PATH`).

## Validation

Rego syntax can be checked without a running plan:

```sh
# With OPA installed:
opa fmt --diff terraform/policy/*.rego

# With Conftest installed:
conftest verify -p terraform/policy/
```

The CI workflow (`tf-policy.yml`) runs the full check on every pull request.
