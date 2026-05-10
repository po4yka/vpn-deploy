# Runbook — incidents

Decision matrix for things going wrong. Pick the row that matches the
symptom; cross-reference the linked runbook for the recovery procedure.

## Decision matrix

| Symptom | Likely cause | Action |
|---|---|---|
| Single client URI leaked / device lost | Per-device | `RUNBOOK-rotate.md` § 1 |
| REALITY private key leaked | Server-wide | `RUNBOOK-rotate.md` § 2, then reissue every client |
| Subscription URL leaked publicly | Token | rotate subscription tokens; see `subscription-delivery-plane-2026 § 17` |
| TLS handshake to VPS fails from many networks at once | IP burned | run `make burn-check` to confirm; then blue-green to new VPS, different ASN if possible |
| Slow / lossy on one network only, fine elsewhere | Routing / ISP-specific | first try `Hysteria2` fallback; if persistent, blue-green to different region |
| `xray run -test -config` fails after deploy | Config bug | `RUNBOOK-rollback.md` § 1 (config rollback, automatic via handler rescue) |
| New Xray release crashes / leaks | Binary | `RUNBOOK-rollback.md` § 2 (binary rollback) |
| Operator workstation compromised | Operator | rotate SSH key + age key + REALITY key + restic password; full credential rotation |
| Lost SSH access (key deleted) | Operator | see § "Lost SSH access" below |
| Lost SOPS age private key | Operator | see § "Lost age key" below; if you set up Shamir split (`docs/AGE-RECOVERY.md`), reconstruct from k shares first |
| Lost Terraform state file | Operator | see § "State loss" below |
| 3x-ui / Marzban / Remnawave panel exposed | Architecture deviation | this stack has no panel by design; if you added one, take it offline NOW |
| Suspected RKN / TSPU active probing | Threat-model | review `vless-graylist-active-probing-defense`; check REALITY target hygiene |
| Mobile network whitelist rolled out for the operator | Threat-model | this is P3 — see `vpn-deployment-hub` § "Phase 3" and the wiki's `whitelist-aware-transport-system-2026` |

## Lost SSH access

You don't have the private key matching `admin_ssh_public_key` on the VPS.

UpCloud:

1. Console → server → Open Web Console → log in as `deploy` (with the
   password you don't have) → impossible.
2. Console → server → Power off → Boot from rescue ISO → mount root disk →
   edit `/home/deploy/.ssh/authorized_keys` → add a new public key.
3. Boot back to disk; SSH in with the new key.
4. Once in, `make rotate-credentials` (technically just push the new key
   via tfvars + ansible playbook) and never use the rescue key again.

If you cannot use rescue, the only path is destroy and recreate the VPS
with a new tfvars `admin_ssh_public_key`. Secrets and Terraform state are
unaffected — `make plan apply inventory wait deploy verify` rebuilds.

## Lost age key

The SOPS secrets file is unrecoverable.

If you encrypted to multiple recipients (recommended for teams), use the
other operator's age key. `sops` tries each recipient until one succeeds.

If you didn't, treat this as a **complete credential leak**:

1. Provision a fresh VPS (new IP, ideally different ASN).
2. Generate a new age keypair, fresh REALITY keypair, fresh per-client
   UUIDs / shortIds / passwords / peer keys, fresh restic password.
3. Distribute new client URIs to every device.
4. Decommission the old VPS once every device has switched.

The encrypted SOPS blob may still be holding valid secrets in storage. age
is computationally hard but not future-proof. Don't keep the old blob
around.

## State loss

Terraform's local state is the only record of which UpCloud resources
belong to this deployment. Lose it and:

- `terraform plan` shows everything as "needs creating".
- `terraform destroy` does nothing (no resources to destroy).
- `make rollback-…` blue-green flows still work but become manual (you
  edit the UpCloud console / API directly).

Recovery path 0 — restore from `make backup-state` snapshot (preferred):

```bash
# State backups live in ~/.config/vpn-provision/state-backups/<provider>-<env>-<timestamp>.tfstate.age
LATEST=$(ls -1t ~/.config/vpn-provision/state-backups/upcloud-prod-*.tfstate.age | head -1)
age -d -i ~/.config/vpn-provision/age.key \
    -o terraform/providers/upcloud/terraform.tfstate \
    "$LATEST"
chmod 0600 terraform/providers/upcloud/terraform.tfstate

terraform -chdir=terraform/providers/upcloud plan
# Expect: no changes
```

Recovery path 1 — state was committed on a partner workstation:

```bash
# Copy the state file back to where Terraform expects it
cp ~/team-shared/vpn-prod-terraform.tfstate \
   terraform/providers/upcloud/terraform.tfstate
```

Recovery path 2 — re-import the existing VPS:

```bash
cd terraform/providers/upcloud
terraform init
terraform import upcloud_server.vpn <SERVER_UUID>
terraform import upcloud_firewall_rules.vpn <SERVER_UUID>
# Validate state matches reality
terraform plan       # should show no changes
```

Find `<SERVER_UUID>` in the UpCloud console (server details → "ID").

After restoration, **back up the state file out of band** (encrypted USB,
1Password Documents, age-encrypted in the same recipient as your
secrets). Don't lose it twice.

## Suspected compromise of the VPS

If you suspect the running VPS has been compromised at the OS level (root
escalation, persistent attacker, unknown process):

1. **Do not** SSH in to "look around" — every observation gives the
   attacker a chance to exfiltrate or alter logs.
2. Power off the VPS via the UpCloud API/console.
3. Snapshot the disk for forensic analysis (UpCloud has a snapshot
   feature; export to a separate region if you can).
4. Treat every credential the VPS could touch as compromised: REALITY
   private key, Hysteria server cert, AWG server private key, restic
   password, every client UUID/password/peer that was on it.
5. Provision a fresh VPS, full credential rotation.
6. Forensic the snapshot offline.

The "disposable nodes" property of this stack means step 5 is fast: it's
the same procedure as a normal first-time deploy.
