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
| One-time bootstrap URL | required | not implemented | gap |
| Scoped payload (per-device profile only) | required | per-device with shared server params | ✓ partial |
| HTTPS endpoint with no access log of paths | required | nginx default access log; per-route log opt-out not enforced | gap |
| Revocation list | implemented in v1.2 | `subscription.revoked_tokens` | ✓ shipped |
| Rate-limit | implemented in v1.2 | `subscription.rate_limit` + burst | ✓ shipped |
| Token expiry per device | required | not implemented (revocation is binary) | gap |
| Delivery host separate from VPN node | required | colocated with VPN (subscription-host role) | gap — single VPS in v1 |
| QR bootstrap flow | required | not implemented | gap |
| Audit log of token reads | recommended | partial — nginx access log only | gap |
| No `Referer` / no `cache` | required | nginx default cache-control = none; referrer policy not set | minor |

## What to ship next

In priority order, deltas that are cheap to land:

1. **One-time bootstrap token** — separate URL space `/bootstrap/<tok>`
   that's deleted after first read. Token stored as hash; payload
   encrypted-at-rest under a key derivable from the token. Closes the
   "stolen subscription URL = forever access" hole.
2. **Per-token expiry** — `subscription.clients[].expires` ISO date;
   nginx Lua check or sub-vhost rebuild on the date.
3. **`access_log off`** for the `/s/` and `/bootstrap/` locations,
   keep only the error log. Removes the URL path from disk logs.
4. **Referrer-Policy: no-referrer** + `Cache-Control: no-store` on the
   subscription locations.
5. **QR bootstrap** — emit a one-time bootstrap URL + QR PNG via
   `scripts/new-client.sh --emit-bootstrap`. Distribute the QR through
   a secure channel; QR is consumed once by the client and the
   bootstrap token is invalidated.

The "delivery host separate from VPN node" gap requires a separate
provider/VPS and falls out of the v1 single-VPS architecture. See
`docs/RUNBOOK-add-fallback.md` and `multi-provider-vpn-fleet-2026` for
the multi-host shape.

## What is NOT a gap

These are documented design choices, not gaps:

- No HTML rendering on subscription endpoints. Wiki agrees.
- No JavaScript on subscription endpoints. Wiki agrees.
- No browser-style cookies. Wiki agrees.
- Plain static payload, no API. Wiki tolerates this as a v1 shape.