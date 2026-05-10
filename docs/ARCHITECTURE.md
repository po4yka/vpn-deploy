# Architecture

This repo materializes the multi-profile access stack from the
`vpn-deployment-hub` MOC in the censorship-bypass vault. The on-disk shape
mirrors the four-tier model:

```
P0 Primary       VLESS + REALITY + XTLS-Vision over RAW/TCP/443
P1 HTTPS         VLESS/Trojan + XHTTP behind nginx (direct, no CDN)
P2 UDP/QUIC      Hysteria2 on UDP/443
P2 Device-VPN    AmneziaWG 2.0 (userspace)
P3 Reachability  Manual — see RUNBOOK-incident.md (relays, WebRTC, roaming)
```

## Layer ownership

| Layer | What it owns | Files |
|---|---|---|
| Terraform | VPS, firewall, SSH key, optional DNS/floating IP | `terraform/providers/<name>/*.tf` |
| cloud-init | Admin user, SSH hardening, python3, marker file | `terraform/shared/cloud-init.yaml.tftpl` |
| Ansible | All runtime state — packages, nftables, xray, nginx, hysteria, awg, monitoring, backup | `ansible/roles/*/` |
| SOPS+age | Secrets at rest | `~/.config/vpn-provision/*.sops.yaml` (outside this repo) |

The boundary is strict: secrets never appear in Terraform state, Terraform
variables, Terraform outputs, cloud-init `user_data`, ansible debug output,
or this repo. Provider credentials live in env vars only.

## Profile-to-role mapping

| Profile | Role | Toggle in `group_vars/all.yml` |
|---|---|---|
| P0 REALITY | `xray` | `vpn.enable_xray_reality` |
| P1 XHTTP | `nginx-xhttp` + xray inbound on 127.0.0.1 | `vpn.enable_nginx_xhttp` |
| P2 Hysteria2 | `hysteria` | `vpn.enable_hysteria` |
| P2 AmneziaWG | `amneziawg` | `vpn.enable_amneziawg` |

Cross-cutting roles: `baseline`, `firewall`, `monitoring`, `backup`,
optional `subscription-host`.

## Disposable nodes

Every node is replaceable. The synthesis-page mantra applies: when an IP
burns or a config drifts, do not hand-repair a snowflake server — recreate
from `git + secrets + Terraform plan`. The state lives in two places:

1. The encrypted secrets file at `~/.config/vpn-provision/`.
2. The Terraform state file (local; back it up out-of-band).

Lose the secrets file → you must rotate every credential.
Lose the Terraform state → you can re-import the VPS, but blue-green
becomes manual. See `RUNBOOK-incident.md` § "State loss".

## Why direct nginx (no CDN)

`docs/CDN-DECISION.md` is the ADR. Short version: as of April–May 2026,
Cloudflare into Russia goes through TSPU-enabled RU PoPs, VK CDN closed
write methods, Yandex CDN dropped anonymous endpoints. CDN-fronted P1 is
no longer a baseline — it is a tactical option.

## Why per-provider Terraform roots

Terraform module sources cannot be variable-driven, so a clean drop-in is
a separate root per provider with identical outputs. The Ansible layer is
provider-neutral; only `scripts/render-inventory.sh` reads
provider-specific outputs (`server_ipv4`, `server_ipv6`, `admin_user`,
`server_hostname`).

## What is intentionally NOT here

- Multi-region fleet automation (Tier 1+ from `multi-provider-vpn-fleet-2026`).
  v1 is single-VPS; second-VPS guidance is in `RUNBOOK-add-fallback.md`.
- Subscription delivery API with revocation and rate-limit middleware.
  v1 ships only `subscription-host` as a static-payload nginx vhost.
- P3 reachability layer automation. By design — the reachability layer is
  network-specific and operator-judged, not deterministically deployable.
- molecule / per-role tests. v2.

## Source-of-truth references

The wiki pages this repo derives from:

- `wikis/infrastructure-operations/wiki/synthesis/reproducible-vps-provisioning-2026.md` — primary
- `wikis/infrastructure-operations/wiki/mocs/vpn-deployment-hub.md` — phase model
- `wikis/infrastructure-operations/wiki/synthesis/multi-profile-access-stack-2026.md` — P0/P1/P2 split
- `wikis/transport-protocols/wiki/synthesis/vless-reality-xtls-vision-production-baseline-2026.md` — REALITY hygiene
- `wikis/transport-protocols/wiki/concepts/cdn-tunneling-closure-april-2026.md` — CDN status
- `wikis/infrastructure-operations/wiki/synthesis/vpn-credential-lifecycle-2026.md` — rotation model
- `wikis/infrastructure-operations/wiki/synthesis/vpn-disaster-recovery-restore-2026.md` — restore model
