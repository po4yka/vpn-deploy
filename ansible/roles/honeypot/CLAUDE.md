# role: honeypot — active-probing detection

## Design decisions

**Same-host honeypot for cheap signal** — binds plausible-looking listeners
(SSH on 2222, "admin panel" on 9000, "metrics" on 9100) that record hits
without responding. Any hit is a probing signal because legitimate users
have no reason to touch them.

**Logs only; no auto-block** — feeds `monitoring`'s probing summary.
Auto-blocking probers is bait — they rotate IPs faster than we can ban.

## What's done well

- **Banner-free** — every honeypot port closes silently after TCP accept.
  No fingerprintable response.
- **Rotated log files** — same retention as `monitoring`.

## Pitfalls

- **Don't expose a honeypot port that legit ops uses** — e.g., if you SSH on
  2222 yourself, do not honeypot 2222. The firewall role validates against
  the effective SSH port.
- **Honeypot ports must be in the firewall allow-list** — otherwise nftables
  drops before the honeypot sees the hit, and you record nothing.
- **Rate-limit log writes** — a Shodan-style scan can fill the disk
  otherwise. logrotate + size limit, both configured.
