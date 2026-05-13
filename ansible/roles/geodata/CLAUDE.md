# role: geodata — MaxMind GeoIP feed

## Design decisions

**MaxMind via license-keyed download, cached on the server** — refreshes
weekly. Used by `firewall` for the geo-block set and by `monitoring` for
ASN labelling.

**License key in SOPS** — not in `defaults/main.yml`. The role refuses to
run if the key isn't present.

## What's done well

- **Atomic database swap** — download to tmp, verify checksum, swap, reload.
  nftables sees a consistent set.
- **DB checksum is asserted** — corrupt downloads fail closed.

## Pitfalls

- **License-free MaxMind tier dies on a schedule** — they have killed it
  before. Have a fallback (IPinfo, DB-IP) ready as a swap-in.
- **GeoIP is wrong at the edges** — RU/UA blocks need ASN-level rules too,
  not just country. `firewall` cross-references both.
- **Don't ship the DB in git** — too big, license-prohibited.
