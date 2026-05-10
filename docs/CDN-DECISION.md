# ADR — Cloudflare CDN is not the RU baseline

**Date:** 2026-05-10
**Status:** accepted
**Scope:** P1 fallback (`nginx-xhttp` role)

## Decision

The `nginx-xhttp` role deploys a **direct foreign VPS** with nginx fronting
443/tcp and proxying a path to the Xray XHTTP inbound on `127.0.0.1`. No
CDN by default.

## Context

Earlier wiki guidance — including parts of `multi-profile-access-stack-2026`
and `server-xray-vless` — used Cloudflare CDN as a P1 fallback baseline,
with hardening recipes for Full (strict) TLS, Origin CA, `CF-Connecting-IP`
real-IP restoration, and Authenticated Origin Pulls. That guidance is
**still technically correct** but **no longer the right default for the
Russian threat model**.

`cdn-tunneling-closure-april-2026` and `cloudflare-russian-pop-tspu-blocking`
document the April–May 2026 status:

| CDN | Status into RU |
|---|---|
| Cloudflare | Reachable, but via Russian PoPs with TSPU enabled. XHTTP passes but the 16 KB curtain is active. Not an independent path — a DPI-shaped one. |
| VK CDN | POST/PUT/PATCH closed for non-legal-entity accounts; XHTTP packet-up and gRPC broken. A verified юрлицо account directly attributes the channel operator under `corporate-vpn-whitelist-rkn`. |
| Yandex CDN | Whitelist mode removed; anonymous endpoints gone. |
| Ngenix / Beeline / CDNvideo | Functional, candidates for closure within weeks. |
| Akamai / CDN77 / Fastly (GET-only) | Work but expensive or narrow. |

Putting CDN in front of P1 in this regime gains nothing (the RU egress is
still through TSPU) and adds a dependency that can fail or change policy
overnight.

## What this means in code

- `roles/nginx-xhttp/templates/site.conf.j2` ships nginx pointed at a
  public CA cert for the domain you control, listening on 443/tcp/udp,
  proxying the XHTTP path to Xray. No `set_real_ip_from`, no
  `CF-Connecting-IP`, no Origin CA logic.
- The `cdn-front` role tag is reserved but not implemented in v1.

## When you might still want CDN

CDN is a **tactical** layer, not a baseline. Reach for it when:

- The direct foreign IP is being IP-blocked at the carrier (the failure
  shape is "TLS handshake never completes from this network, but completes
  from a different one"), and a non-RU CDN PoP is reachable.
- You need short-term cover while rotating to a new VPS IP.
- You explicitly want browser-shaped traffic for a small, monitored
  deployment, and you're comfortable losing it within weeks.

In those cases, see `multi-profile-access-stack-2026` § "Fallback A" for
the full Cloudflare hardening recipe (Full strict, Origin CA, AOP, real-IP
restoration). Treat that recipe as a **separate role** to add later, not a
flag flip on `nginx-xhttp`.

## When NOT to use CDN under any circumstances

- **VK CDN, Yandex CDN, RU-domestic CDN** — directly attributes the
  operator and is closing for non-corporate accounts.
- **Cloudflare as the *only* path** — single point of policy failure.
- **As a "whitelist bypass"** — CDN reachability is not whitelist
  reachability; that's a different layer (P3 in the hub model).

## How this is enforced

- The `nginx-xhttp` role has no CDN-specific code paths.
- The `.gitleaks.toml` has no Cloudflare-specific exemptions.
- This document is referenced from `README.md` and `ARCHITECTURE.md` as
  the canonical answer when someone asks "why isn't CDN the default."

## Revisit triggers

Re-evaluate this decision if:

- Cloudflare reverses the RU-PoP-via-TSPU situation.
- A non-RU CDN provides documented, stable, non-TSPU paths into RU.
- The threat model changes (e.g., the operator is no longer targeting RU,
  or the operator wants browser camouflage as the dominant property).

Until then, `nginx-xhttp` is direct.
