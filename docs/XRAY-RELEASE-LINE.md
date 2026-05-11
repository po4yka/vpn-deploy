# Xray-core release-line tracker

Pinned version: see `secrets/prod.secrets.example.yaml` →
`xray.version`. The repo policy is: stay on the GitHub-tagged Latest
build, never on a Pre-release in production.

This file tracks notable behavioural changes per release so an
operator deciding when to bump the pin can see the surface they're
crossing.

## v26.2.6 — 2026-02-06

- **XHTTP CDN bypass options** — new headers that make XHTTP look
  more like organic browser traffic, useful for CDN-fronted XHTTP.
- **Finalmask UDP expansion** — Finalmask now covers WireGuard UDP,
  Shadowsocks AEAD/2022 UDP. Variants `XDNS`, `XICMP`, `header-*`,
  `mkcp-*` added.
- **Dynamic Chrome User-Agent** — Xray-core HTTP requests now use a
  dynamic Chrome UA by default, replacing the static `Go-http-client`
  string. No config change required.

## v26.3.27 — ~2026-03-27 (current Latest as of 2026-05-10)

- **REALITY auto-probe defence** improvements.
- **ECH full mode** — `echForceQuery` default changed to `"full"`.
- **Finalmask Sudoku** byte-distribution obfuscation. The
  `vpn.xray_finalmask` group_vars toggle in this repo enables this.
- Warning emitted when listening on non-443 ports — non-443 listeners
  are pushed onto the IP blacklist faster.
- Warning when REALITY target SNI is Apple/iCloud — flagged for fast
  ban.
- New `pinnedPeerCertSha256` (outbound-side); deprecates
  `allowInsecure`.
- New `trustedXForwardedFor` sockopt for XHTTP/WS inbounds. The
  `vless-xhttp-localhost` inbound in this repo's xray config template
  uses it.

## v26.4.x — Pre-release as of 2026-04-30

- Carries Xray v26.4.25 + KCP obfs + TCP Masks (per 3xui-v2-9-releases-
  april-2026 digest). KCP obfs is an additional UDP transport surface;
  TCP Masks is a new Finalmask family for TCP.
- Production policy: stage-only until promoted to Latest.

## v26.5.3 — Pre-release as of 2026-05-09

**Breaking changes — schema migration required before upgrading:**

- `echForceQuery` field is **removed**. ECH is now always forced when
  configured. Any config containing `echForceQuery` will fail to
  parse. The `scripts/check-secrets-coverage.py` guard fails the
  schema check if the field is present.
- ALPN `["h2","http/1.1"]` is now permitted in the **outer TLS layer**
  for WSS / HUS transports. Prior versions rejected this; the
  rejection itself was an Xray-specific fingerprint.
- New `finalRules` egress filter (ALPN/PQE-aware routing rule type).
- ICMP tunnel transport added.
- **Post-Quantum Encryption (PQE)** for VLESS — pre-release, fingerprint
  considerations apply (larger `key_share` extension makes the
  ClientHello distinct from typical browser traffic until Chrome's
  ML-KEM rollout normalises in RU traffic).

## Production rollout policy

1. Bump `xray.version` in the secrets schema and SOPS files only when
   the target tag is GitHub-tagged Latest, not Pre-release.
2. Run `make validate` — it executes `check-secrets-coverage.py`,
   which guards against the `echForceQuery` removal at PR time.
3. Run on a staging cohort for ≥48 hours before fleet rollout.
4. Capture `xray test -config` output in the deploy log; refuse to
   restart xray on a host where the new config fails parse.
5. Keep the previous binary at `/opt/xray/bin/xray.prev` for
   single-flag rollback (`make rollback-xray
   ROLLBACK_XRAY_VERSION=vX.Y.Z`).

## Revisit cadence

Re-read this page on every Xray-core minor bump and at the start of
each quarter. Stale rollout instructions are worse than no
instructions.