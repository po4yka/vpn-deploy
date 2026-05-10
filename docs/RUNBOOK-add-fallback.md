# Runbook — add a fallback VPS

v1 ships single-VPS. For a true multi-VPS / multi-ASN posture (Tier 1+
from `multi-provider-vpn-fleet-2026`), here's how to extend.

## Two patterns

| Pattern | When | Effort |
|---|---|---|
| Same provider, same role | Need a hot spare for blue-green | Low |
| Different provider / ASN, same role | Want orthogonal failure domain | Medium |
| Different role (one P0, one P1+P2) | Want clean role separation | Medium |

## Pattern 1 — hot spare on UpCloud

Use a separate `ENV` value to keep two parallel root states without
fighting Terraform's `prevent_destroy`.

```bash
# Create a second tfvars
cp terraform/providers/upcloud/environments/prod.tfvars \
   terraform/providers/upcloud/environments/spare.tfvars

# Edit: change server_name (e.g. vpn-prod-fi2) and zone (e.g. de-fra1)
$EDITOR terraform/providers/upcloud/environments/spare.tfvars

# Provision and deploy
ENV=spare make init plan apply inventory wait dry-run deploy verify
```

Both VPSes now share the same secrets and same Ansible roles. They have
different IPs, different REALITY private keys (REALITY private key is in
secrets — to truly differ you need a second secrets file or a per-host
override). For a hot spare in the same provider, sharing REALITY material
is acceptable for a short period.

To switch traffic: change DNS / subscription URLs to point at the spare,
and decommission the original (`make ENV=prod terraform … destroy` after
removing `prevent_destroy`).

## Pattern 2 — different provider / ASN

Implement the `hetzner` or `vultr` Terraform stub:

```bash
# 1. Copy the UpCloud module shape
cd terraform/providers/hetzner
# Replicate variables.tf / main.tf / firewall.tf / outputs.tf shape from
# providers/upcloud/, swap resources for hcloud_*. Outputs MUST match:
#   server_ipv4, server_ipv6, admin_user, server_hostname.
# See providers/hetzner/README.md for the implementation outline.

# 2. New environments file
mkdir -p environments
$EDITOR environments/prod.tfvars

# 3. Provision and deploy under the same ENV but a different PROVIDER
PROVIDER=hetzner make init plan apply inventory wait dry-run deploy verify
```

Now you have two VPSes in different ASNs. To make them serve different
client cohorts:

- Use a per-cohort subscription URL on `subscription-host`.
- Send cohort A's traffic to the UpCloud VPS, cohort B's to the Hetzner
  one. If cohort A's path degrades, the operator switches that cohort's
  subscription URL to a different VPS.

This is the minimum useful cohort split. The full model
(`multi-provider-vpn-fleet-2026`) covers blast-radius caps and migration
playbooks.

## Pattern 3 — separate roles per VPS

Best for production. One VPS hosts only P0 (REALITY direct), another
hosts P1+P2 (XHTTP + Hysteria + AWG). They have no shared protocol
material; a compromise of one doesn't leak the other.

```bash
# VPS 1 — only REALITY
$EDITOR terraform/providers/upcloud/environments/p0.tfvars   # enable_hysteria=false
$EDITOR ~/.config/vpn-provision/p0.secrets.sops.yaml         # only xray.* fields

# Override role toggles per environment by editing playbooks/site.yml
# OR keep one site.yml and use:
ANSIBLE_TAGS="xray" ENV=p0 make decrypt deploy
```

For a separate-role split, also split the `vpn.enable_*` toggles in
`group_vars/all.yml` per host group. The simplest layout is host_vars:

```bash
mkdir -p ansible/host_vars
cat > ansible/host_vars/vpn-prod-p0 <<EOF
vpn:
  enable_xray_reality: true
  enable_nginx_xhttp: false
  enable_hysteria: false
  enable_amneziawg: false
EOF

cat > ansible/host_vars/vpn-prod-p1p2 <<EOF
vpn:
  enable_xray_reality: false
  enable_nginx_xhttp: true
  enable_hysteria: true
  enable_amneziawg: true
EOF
```

Then `render-inventory.sh` puts both hosts in `[vpn]` and a single
`make deploy` configures them differently.

## Operational consequences of multi-VPS

- **Secrets get bigger**: separate REALITY keypairs per VPS, separate
  Hysteria server certs, separate AWG server keys. Decide whether you
  want one secrets file with all VPSes or one per VPS.
- **Restic gets bigger**: per-VPS local repos, or one remote bucket with
  per-VPS prefixes.
- **Subscription delivery starts mattering**: when there's one VPS, you
  hand-edit URIs. When there are two+, you need a real subscription
  endpoint that can hand each device the right cohort.
- **Health checks and failover** become explicit: clients need
  selector/urltest logic in sing-box / NekoBox to actually use the
  fallback VPS without a manual switch. See
  `client-profile-policy-runbooks-2026` in the wiki.

## What this repo intentionally does NOT automate

- Multi-VPS coordination (no shared state plane).
- Cohort assignment / per-device subscription rendering with revocation.
- Burned-ASN detection.

Those are upstream wiki concerns. v2 may bring some of them in; for v1
the answer is: pick a pattern above, run it twice, and treat the second
run as deliberate operator action.
