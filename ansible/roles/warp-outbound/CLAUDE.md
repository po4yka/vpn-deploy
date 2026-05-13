# role: warp-outbound — server egress through Cloudflare WARP

## Design decisions

**Health-gated activation** — `vpn.enable_warp_outbound` flips the toggle,
but the role only swings outbound routing *after* WARP confirms it's up.
Failure leaves the previous egress intact.

**SOCKS5 at 127.0.0.1:40000** — WARP runs in `proxy` mode; Xray's
`outbound.protocol: socks` points at it. Don't try kernel-level routing
through WARP — too easy to lock yourself out.

## What's done well

- **Reversible** — disabling the toggle and re-running puts outbound routing
  back. Tested in `RUNBOOK-rollback.md`.
- **Version-tolerant CLI** — both `warp-cli set-mode proxy` (old) and
  `warp-cli mode proxy` (new) are tried; the role doesn't pin to one syntax.

## Pitfalls

- **WARP packages have a Cloudflare repo with a key rotation history** —
  pin the apt-key once and don't auto-refresh; manual update via the
  release-line tracker.
- **WARP and IPv6 don't get along on some kernels** — disable v6 on the WARP
  interface if you see ICMPv6 floods.
- **`warp-cli register` runs unattended-only on first boot** — if it fails
  mid-deploy, manual `warp-cli register` is needed before re-running.
- **WARP changes egress IP** — anything keying on the server's public IPv4
  (asn-drift, burn-check) sees a different reality through WARP. Probes must
  account for this when WARP is on.
