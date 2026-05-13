# vpn-deploy — root knowledge file

## Vision

Reproducible, layered IaC for a four-tier multi-profile VPN stack
(P0 VLESS+REALITY+Vision, P1 nginx+XHTTP direct, P2 Hysteria2 + AmneziaWG,
P3 manual reachability). Threat model is RU-internet / TSPU-aware.

Nodes are disposable. Secrets are SOPS+age. The Makefile is the canonical
operator surface; `vpnd/` is a convenience CLI in front of it (see
`docs/GOAL-vpnd-cli.md`).

## Hard rules

- No secrets in git, Terraform state, TF vars/outputs, cloud-init `user_data`,
  Ansible debug, or screenshots. Provider credentials in env vars only.
- No public admin panel. No remote installer piped to root shell.
- One UUID / shortId / peer key per device — never shared.
- Pinned versions; pre-releases through staging only.
- Gitleaks gates CI.
- CDN is **not** the RU baseline (see `docs/CDN-DECISION.md`).

## Layered ownership

```
Terraform     → VPS, firewall, SSH key, DNS, floating IP
cloud-init    → admin user, SSH hardening, python3, marker file
Ansible       → all runtime state (packages, nftables, xray, nginx, …)
SOPS+age      → secrets at rest, outside the repo
vpnd (Rust)   → convenience CLI in front of Make/Terraform/Ansible/SOPS
```

Strict boundary: nothing crosses these except via documented interfaces.

## Per-folder CLAUDE.md system

Every meaningful folder has a `CLAUDE.md`. Together they form a
self-healing knowledge layer. Format: three sections — **Design decisions**
(WHY), **What's done well** (preserve), **Pitfalls** (the most valuable).
Keep each under ~40 lines. Update as part of the PR, not a separate task.

Current coverage:

```
CLAUDE.md                                — this file
ansible/CLAUDE.md                        — playbook order, group_vars contract
ansible/roles/<name>/CLAUDE.md           — 16 roles, all backfilled
terraform/CLAUDE.md                      — provider-root strategy
terraform/providers/<name>/CLAUDE.md     — upcloud (primary), hetzner, vultr
terraform/shared/CLAUDE.md               — cloud-init contract
scripts/CLAUDE.md                        — shell/python conventions
tests/CLAUDE.md                          — unit + snapshot + molecule + tf-test layers
vpnd/CLAUDE.md                           — Rust convenience CLI
docs/GOAL-vpnd-cli.md                    — vpnd spec (Phase 1–3)
docs/CDN-DECISION.md                     — ADR: CDN is not the RU baseline
```

## Development

```bash
make ci-fast            # render + secrets coverage + snapshot + schema + syntax + pytest
make molecule-test ROLE=<name>
make tf-test            # terraform mock_provider tests
cd vpnd && cargo check  # convenience CLI typecheck
cd vpnd && cargo test   # snapshot tests for the recipient page
```

## Versioning

release-please drives versioning from Conventional Commits. Don't edit
`CHANGELOG.md` by hand. One bump per session by intent.

## When the user says "remember"

Save to the relevant folder's `CLAUDE.md`, not to a memory system. The
per-folder knowledge layer is the durable artifact.
