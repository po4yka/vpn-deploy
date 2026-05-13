# role: watchdog — self-healing service supervision

## Design decisions

**Two-level supervision** — systemd is layer 1 (Restart=on-failure). The
watchdog role adds layer 2: a cron job that probes critical endpoints
(Xray Reality handshake, nginx 443, Hysteria UDP) and kicks systemd if
they're stuck-but-not-crashed.

**Bounded** — max 3 kicks per hour. Beyond that, page the operator (via the
audit log; alerting is operator-side).

## What's done well

- **Probes hit the public surface, not internals** — measures the symptom
  the user sees.
- **Idempotent** — kicking an already-healthy service is a no-op.

## Pitfalls

- **A flapping service masks real issues** — if the watchdog keeps kicking,
  that's a P1 incident, not "everything is fine". The probing-summary
  surfaces kick counts.
- **`systemctl restart` during config rollout races deploy** — the watchdog
  is paused (via a sentinel file) during Ansible runs. Don't remove the
  pause unless you've added a lockfile dance.
- **Cron timing skew** — minute-granularity is enough; don't move to
  `OnUnitActiveSec` 30s — that's noise, and TSPU canaries depend on stable
  cron offsets.
