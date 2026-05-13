# role: probe-ratelimit — Xray-side active-probing throttle

## Design decisions

**Per-IP rate limit on failed handshakes** — Xray's Reality rejects bad
handshakes silently, but a probing IP can still burn CPU and noise the logs.
This role adds an nft chain that drops repeated failed-handshake sources.

**Threshold is conservative** — defaults are 20 failed handshakes / minute /
IP. Aggressive limits break NAT'd users whose hands-haker churns.

## What's done well

- **Whitelist for known prober buckets** — Shodan/Censys ranges are *not*
  whitelisted (we want them dropped); CloudFront/Cloudflare edges *are*
  (legitimate users from those ranges hit us).
- **Ephemeral state** — the per-IP counter set is tmpfs-backed; reboots wipe.

## Pitfalls

- **Rate-limiting at the firewall layer ≠ at the Xray layer** — Xray sees
  the source IP only if no NAT/proxy is in front. CDN-fronted paths
  effectively limit by the CDN edge IP, which is useless. Disable this role
  when `cdn-front` is on.
- **Don't tune below the carrier-grade NAT threshold** — RU mobile NAT
  pools share an IP across thousands of users; a strict limit takes out
  legitimate clients first.
- **Pair with `honeypot`** — the same IPs hitting honeypot ports often
  trigger here. Cross-correlate in `probing-summary`.
