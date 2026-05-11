# AmneziaWG cohort obfuscation profiles

The `amneziawg_secrets.{jc,jmin,jmax,s1,s2,h1,h2,h3,h4}` block is what
turns plain WireGuard into AmneziaWG. Defaults work most places, but
specific Russian ISPs apply WireGuard-shaped DPI rules that need
cohort-specific tuning. This file captures the community-tested
starting points; verify on the target network before locking.

## Why this matters

Plain WireGuard Initiation messages are deterministically identifiable:
148 bytes, fixed field layout (4-byte type, 4-byte sender index, 32-byte
ephemeral public key, 48-byte encrypted static key, 28-byte encrypted
timestamp, 16-byte MAC1, 16-byte MAC2). TSPU/DPI matches on that size
+ layout, then applies periodic 20–30 s stalls to "kill the
reconnection cycle" rather than RST. AmneziaWG randomises the size
(`Jc` junk-count, `Jmin/Jmax` junk-length bounds) and headers
(`H1..H4`) so the Initiation no longer fits the rule.

Reference: censorship-bypass wiki page
`tspu-dpi-internals/wiki/concepts/wireguard-rtk-south-amneziawg-bypass`.

## Known-good profiles

| Cohort | Jc | Jmin | Jmax | S1 | S2 | H1..H4 |
|---|---|---|---|---|---|---|
| RTK South (Rostov Oblast, 2026-05) | 4 | 10 | 50 | 0 | 0 | 1,2,3,4 |
| MTS / Beeline / MegaFon mobile (baseline) | 4 | 40 | 70 | 50 | 100 | random per peer |
| Home ISP, broad-rule (default) | 4 | 40 | 70 | 50 | 100 | random per peer |

H1..H4 should be **random integers per peer** outside the RTK-South
case — using literal `1,2,3,4` everywhere creates a template the
censor can train on. Generate four random 32-bit unsigned ints with:

```bash
for i in 1 2 3 4; do
  printf 'h%d: %d\n' "$i" "$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
done
```

## When to deviate from the profile

- The handshake never completes from a specific carrier or city → try
  the RTK-South values as a known-good baseline, then re-randomise H1..H4.
- Handshake completes but stalls every ~30 s → keep current H1..H4;
  the issue is upstream rate-limiting, not the Initiation shape.
- Handshake works but client reports "sometimes 3–4 retries" → that
  matches the observed RTK-South probabilistic behaviour; no further
  change needed.

## Operational notes

- The same H1..H4 set must be deployed on both server and client. If
  you rotate H values on the server, push the new client config (the
  `new-client.sh` flow handles this when `amneziawg_secrets.h*` is
  bumped).
- A single host with multiple cohorts requires multiple AWG instances
  (different ports + different H values). The v1 layout assumes a
  single cohort per host; multi-cohort is on the road map.
