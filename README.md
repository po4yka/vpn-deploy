# vpn-deploy

Reproducible VPN deployment automation for the multi-profile access stack
(`P0` VLESS+REALITY+Vision → `P1` nginx+XHTTP direct → `P2` Hysteria2 +
AmneziaWG). Built around the model from
`reproducible-vps-provisioning-2026`: Terraform owns cloud resources,
cloud-init does first-boot bootstrap, Ansible owns runtime state, and
secrets live outside the repo (SOPS + age).

## Layers

```
Terraform     → VPS, firewall, SSH key, optional DNS/floating IP
cloud-init    → admin user, SSH hardening, python3, marker file
Ansible       → packages, nftables, xray, nginx, hysteria, AWG, monitoring, backup
Secrets       → SOPS-encrypted file outside the repo (~/.config/vpn-provision/)
```

Every layer is dry-runnable. Every layer has a rollback path. Nodes are
disposable: when an IP burns, recreate from git + secrets, do not repair.

## Provider support

| Provider | Status |
|---|---|
| UpCloud | primary (v1) |
| Hetzner | stub, ready for v1.1 |
| Vultr | stub, ready for v1.1 |

Switch via `make PROVIDER=upcloud …`.

## Where to start

1. `docs/QUICKSTART.md` — zero-to-working in ~30 minutes.
2. `docs/ARCHITECTURE.md` — how this repo maps to the P0–P3 stack.
3. `docs/CDN-DECISION.md` — explicit ADR: Cloudflare CDN is **not** the RU
   baseline; nginx-xhttp role is direct-only by default.
4. `docs/SECRETS.md` — SOPS+age model, age-key recovery, rotation.
5. `docs/AGE-RECOVERY.md` — Shamir-split the age key for k-of-n recovery.
6. `docs/RUNBOOK-deploy.md` — full deploy procedure.

Operational runbooks: `docs/RUNBOOK-{rotate,rollback,incident,restore,add-fallback}.md`.

## Make targets

```
# Core lifecycle
make init        # terraform init for the chosen PROVIDER
make validate    # fmt, validate, gitleaks, ansible-lint
make decrypt     # sops --decrypt → /tmp/vpn-<env>.secrets.yaml
make plan        # terraform plan -out=<env>.tfplan
make apply       # terraform apply <env>.tfplan
make inventory   # render Ansible inventory from terraform outputs
make wait        # wait for cloud-init to finish on the new VPS
make dry-run     # ansible-playbook --check --diff
make deploy      # ansible-playbook site.yml
make verify      # post-deploy verification playbook
make clean       # shred decrypted secrets

# Rollback / rotation
make rollback-xray ROLLBACK_XRAY_VERSION=vX.Y.Z
make rollback-config
make rotate-credentials

# Operations
make destroy                              # safe, double-confirmation destroy
make backup-state                         # age-encrypt local TF state
make burn-check                           # external IP reachability probe
make diff-secrets                         # drift detection
make emit-singbox CLIENT=<name>           # full sing-box client JSON
make install-hooks                        # one-time pre-commit setup
make molecule-test ROLE=<name>            # role-level idempotence test
```

## Hard rules

- No secrets in git, in Terraform state, in Terraform variables/outputs, in
  cloud-init `user_data`, in Ansible debug output, or in screenshots.
- No public admin panel. No remote installer piped into a root shell.
- One UUID / one shortId / one peer key **per device**, never shared.
- Pinned versions. Pre-release versions go through staging only.
- CI gate: gitleaks must pass with the `.gitleaks.toml` rules in this repo.

## License

Public domain (see `LICENSE`).
