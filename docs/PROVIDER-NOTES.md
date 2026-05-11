# Provider notes

## ASN / hoster risk tiers (RU threat model, 2026-05)

Source: `censorship-bypass/wikis/infrastructure-operations/wiki/concepts/server-anti-detection-checklist-2026`
and the TCP-freeze observation in `tspu-dpi-internals/wiki/concepts/tcp-connection-freezing`.

| Tier | Provider / ASN | Notes |
|---|---|---|
| Avoid | Cloudflare AS13335 | TSPU peering at DME/KJA/LED; 8–16 KB cut; see `CDN-DECISION.md` |
| Avoid | OVH AS16276, Hetzner AS24940, DigitalOcean AS14061 | "Foreign datacenter" ASN bucket triggers TCP freeze (~14–25 KB on mobile RU) |
| Avoid | JustHost AS26383, VDSina AS216071 | Frequently flagged as VPN-tenant ranges; high churn |
| Acceptable | UpCloud (current primary) | Not on the public RKN/TSPU watch lists as of 2026-05; verify ASN before rollout |
| Preferred | Hostkey, nuxt.cloud (DE/NL), hostvds.com (FI) | Smaller, less-flagged ranges per community testing |

For a full deploy this primarily affects the **egress** IP, not the
ingress: a node that ingresses on REALITY/TCP and egresses through the
same VPS IP will hit the TCP-freeze rule when the upstream is on one of
the "Avoid" ASNs. Split-hop egress (separate exit IP, e.g. via WARP) is
documented in `docs/ARCHITECTURE.md` once that role lands.

## UpCloud (primary, v1)

UpCloud is the primary provider in v1. Resource shape:

- `upcloud_server` — the VPS itself, with `template { … }` cloning a public
  storage template UUID into the root disk.
- `upcloud_firewall_rules` — attached to the server. Note that UpCloud's
  firewall is on the hypervisor, not the OS — so even if `nftables` is
  misconfigured, UpCloud's rules apply first.
- `network_interface { type = "public" }` + `{ type = "utility" }` are
  required for the server to be reachable; `private` interfaces are
  optional for multi-VPS networking (out of scope for v1).
- Daily snapshots are enabled in `template.backup_rule` (7-day retention).
  This is a hypervisor-level safety net **separate from** restic backups,
  which contain the configs you can restore onto a fresh VPS.

### Useful UpCloud zones for EU baseline

- `fi-hel1` — Helsinki (default in `prod.tfvars.example`)
- `de-fra1` — Frankfurt
- `nl-ams1` — Amsterdam
- `pl-waw1` — Warsaw

Picking a zone is a routing-quality decision, not a censorship-evasion
one. Pick the zone closest to your client cohort's egress.

### Storage template UUIDs

UpCloud rotates template UUIDs as new minor versions ship. Always pin a
specific UUID in `tfvars`, never a slug. List candidates with:

```bash
upctl storage list --public --template
```

Pick the most recent Debian 13 or Ubuntu 24.04 minimal cloud image.

### Provider auth

```bash
export UPCLOUD_USERNAME='vpn-deploy'   # sub-account, not master
export UPCLOUD_PASSWORD='…'
```

Use a sub-account with only the rights this stack needs. Never bake
credentials into `*.tfvars` — the provider reads them from env.

### Limits to be aware of

- Hypervisor firewall has a per-server rule cap. The base 5–7 rules from
  `firewall.tf` are well within it; if you add per-CIDR carve-outs to the
  point of dozens, watch the cap.
- Object storage / "Managed Database" features are out of scope here.
- API rate limit: low, but Terraform's default backoff handles it.

## Hetzner (stub, v1.1)

Will use:

- `hcloud_server`, `hcloud_ssh_key`, `hcloud_firewall`,
  `hcloud_firewall_attachment`.
- ASN AS24940 — flagged in the TCP-freeze rule on RU mobile networks
  (see the "Avoid" tier above). Hetzner remains useful for non-RU-mobile
  cohorts and for development; rotate IPs more aggressively than UpCloud.
- Cheaper than UpCloud per spec; smaller geographic surface (EU-heavy +
  US East/West, no APAC).
- IPv6 must be explicitly enabled in `tfvars`; off by default on cheaper
  plans.

## Vultr (stub, v1.1)

Will use:

- `vultr_instance`, `vultr_ssh_key`, `vultr_firewall_group`,
  `vultr_firewall_rule`.
- Wider region coverage than UpCloud / Hetzner.
- IP reputation is more variable; rotate regions when burn-check shows
  a region's prefix is RKN-blocked.

## What every provider stub must export for inventory compatibility

`scripts/render-inventory.sh` reads exactly these Terraform outputs:

- `server_ipv4` — required
- `server_ipv6` — optional, may be `null`
- `admin_user` — required
- `server_hostname` — required

Stubs that don't export these names will need a parallel branch in the
script. Keep the names identical to avoid that.
