# role: monitoring — local-first observability

## Design decisions

**No external telemetry** — Prometheus node_exporter listens on 127.0.0.1
only. `scripts/probing-summary.sh` pulls metrics via SSH on demand. Nothing
egresses unless the operator runs it.

**Active-probing log is the load-bearing signal** — `/var/log/probing/` keeps
nginx access patterns, Xray failed-handshake counts, and honeypot hits.
`scripts/probing-summary-remote.py` rolls these up.

## What's done well

- **Logrotate with retention** — 7 days local, then deleted. No long-term
  log corpus to subpoena.
- **`tspu-canary` integration** — daily canary probes from an in-cohort box
  feed into the same probing-summary view.

## Pitfalls

- **node_exporter on a public port = fingerprint** — never bind anything
  other than 127.0.0.1. Verified by `verify.yml`.
- **Honeypot port choice matters** — if you put a honeypot on a port that
  legit traffic also hits, you'll get false positives. Coordinate with
  `firewall/CLAUDE.md`.
- **No alerting included** — by design. Alerting is operator-side, via
  `install-operator-crons` on a workstation, not on the server.
