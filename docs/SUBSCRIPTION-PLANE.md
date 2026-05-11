# Subscription plane — gap matrix

Source: `censorship-bypass/wikis/infrastructure-operations/wiki/synthesis/subscription-delivery-plane-2026`.

This document compares the wiki's recommended subscription-delivery
architecture against what `roles/subscription-host` actually ships, so
the gap is visible and the next iteration has a backlog.

## Architecture target (wiki)

```
Control plane (Terraform + Ansible + secrets)
  └─ renders scoped per-device payloads
       └─ Delivery host (separate from VPN node)
            ├─ public HTTPS endpoint:
            │    /s/<opaque-token>
            │    /bootstrap/<one-time-token>
            ├─ stores: token hashes, scopes, expiry; encrypted payloads
            └─ does NOT store: REALITY privateKey, provider tokens,
                               deploy SSH keys, master subscription
```

Key principle: a subscription URL is a **bearer secret** (RFC 6750),
so it must be issued, scoped, expirable, and revocable.

## Gap matrix

| Property | Wiki target | This repo today | Gap |
|---|---|---|---|
| Per-device opaque token | required | partial — one token per `clients[*]` | ✓ shape OK |
| Token stored as hash, not plaintext | required | plaintext in SOPS-encrypted secrets | secrets are encrypted at rest but the host serves plaintext payloads keyed by plaintext tokens |
| One-time bootstrap URL | required | `/bootstrap/<token>` via vpn-bootstrap service | ✓ shipped |
| Scoped payload (per-device profile only) | required | per-device with shared server params | ✓ partial |
| HTTPS endpoint with no access log of paths | required | `access_log off` on `/sub/` and `/bootstrap/` | ✓ shipped |
| Revocation list | implemented in v1.2 | `subscription.revoked_tokens` | ✓ shipped |
| Rate-limit | implemented in v1.2 | `subscription.rate_limit` + burst | ✓ shipped |
| Token expiry per device | required | `<token>.meta` sidecar; vpn-bootstrap returns 410 after `expires` | ✓ shipped (bootstrap only — see notes) |
| Delivery host separate from VPN node | required | colocated with VPN (subscription-host role) | gap — single VPS in v1 |
| QR bootstrap flow | required | `issue-bootstrap.sh --qr` writes a PNG | ✓ shipped |
| Audit log of token reads | recommended | partial — nginx access log only | gap |
| No `Referer` / no `cache` | required | explicit `Cache-Control: no-store` + `Referrer-Policy: no-referrer` on both `/sub/` and `/bootstrap/` | ✓ shipped |

## What to ship next

The five "ship next" items from earlier iterations are now landed.
Remaining gaps in priority order:

1. **Per-token expiry on `/sub/`** — today's expiry only covers
   `/bootstrap/` (the Python service that owns its own check). The
   static-payload `/sub/` location has no expiry mechanism; needs
   either nginx Lua or moving `/sub/` behind the same Python service.
2. **Audit log of token reads** — capture which token was consumed
   when, into an append-only structured log separate from nginx.
   Useful for forensics after a credential leak.
3. **Hashed token storage** — payloads under `/var/lib/vpn-sub/<token>`
   are currently keyed by plaintext token. A hash-keyed layout
   (`/var/lib/vpn-sub/<sha256(token)>`) would mean disk theft alone
   doesn't yield usable subscription URLs.
4. **Delivery host separate from VPN node** — requires a separate
   provider/VPS and falls out of the v1 single-VPS architecture. See
   `docs/RUNBOOK-add-fallback.md` and `multi-provider-vpn-fleet-2026`
   for the multi-host shape.

## What is NOT a gap

These are documented design choices, not gaps:

- No HTML rendering on subscription endpoints. Wiki agrees.
- No JavaScript on subscription endpoints. Wiki agrees.
- No browser-style cookies. Wiki agrees.
- Plain static payload, no API. Wiki tolerates this as a v1 shape.