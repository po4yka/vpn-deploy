# role: xray — P0 VLESS+REALITY+Vision

## Design decisions

**Single source of REALITY config** — `templates/xray-config.json.j2` is the
SOT for the Reality inbound. Other roles (firewall, nginx-xhttp) read ports
from `defaults/main.yml`; they never copy the inbound config.

**Pinned binary** — Xray version is pinned in `defaults/main.yml`; upgrades
go through `docs/XRAY-RELEASE-LINE.md`. The release-line tracker exists
because v26.2.6 → v26.5.3 had silent flow-mode breakage on some clients.

**Listen 127.0.0.1 when nginx fronts** — when `vpn.enable_nginx_xhttp` is on,
the XHTTP inbound binds to 127.0.0.1 only. The Reality inbound stays on
`0.0.0.0:443`.

## What's done well

- **Idempotent inbound rebuild** — handler `restart xray` only fires when the
  rendered config changed, not on every play.
- **Multi-cohort support** — `vpn.xray_cohorts` is a list; each cohort gets
  its own inbound with its own `serverNames`, `shortIds`, flow_mode, and
  finalmask. See `docs/MULTI-COHORT.md`.
- **Backup-before-write** — the previous config is copied to `.prev` so
  `rollback-config.yml` has a target.

## Pitfalls

- **Reality `dest` is single-target per inbound** — you cannot have a single
  inbound fall back to multiple targets. Multi-cohort needs multiple inbounds.
  Don't try to express this in `settings.fallbacks` — those only apply *after*
  Reality has authenticated the client.
- **Short ID length must be even hex** — odd-length values silently break
  some clients (sing-box ≤ 1.10). `validate-reality-target.sh` checks this.
- **Flow `xtls-rprx-vision` and XHTTP are mutually exclusive** — the XHTTP
  inbound must run with `flow: ""` (empty string), not omit the key.
- **`serverNames` first entry is special** — uTLS clients send the first
  entry as SNI. Rotating its order *is* a config change even though the set
  is identical.
- **Binary-pin drift on apt-update** — never `apt upgrade xray` blindly;
  the binary is hash-pinned via the release-line tracker.
