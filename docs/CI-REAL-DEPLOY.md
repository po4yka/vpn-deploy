# Real-VPS CI deploy gate

The `real-vps-deploy` workflow approximates a production deploy in
GitHub Actions: provision an ephemeral UpCloud VPS, run the full
playbook + verify + smoke-test against it, destroy it. Docker
molecule scenarios catch most regressions; this gate catches the
ones that depend on the real cloud environment (template behaviour,
cloud-init quirks, provider firewall ordering, real systemd unit
startup, etc.).

## When it runs

The workflow is intentionally NOT triggered on every push — it burns
provider credit and takes ~15-20 minutes per run. Two triggers:

  * **workflow_dispatch** — manual: Actions → "real-vps-deploy" →
    Run workflow. Optional `zone` input.
  * **pull_request labeled `ci-real-deploy`** — a maintainer
    consciously adds the label when a PR touches provisioning,
    role ordering, or cloud-init.

The job refuses to start on a fork PR (secrets aren't exposed there)
and uses a `real-vps-deploy` concurrency group so two runs never race
against the UpCloud account.

## Required GitHub secrets

| Secret | Purpose |
|---|---|
| `UPCLOUD_USERNAME` | UpCloud sub-account with VPS create + destroy |
| `UPCLOUD_PASSWORD` | sub-account password — use a tightly scoped sub-account, NOT the master account |
| `CI_SOPS_AGE_KEY` | age private key staged onto the runner so any later step needing SOPS works; CI does not commit an encrypted blob |
| `CI_SSH_PRIVATE_KEY` | SSH key the ephemeral VPS authorises; not reused outside CI |
| `CI_UPCLOUD_TEMPLATE_UUID` | Debian-13 / Ubuntu-24.04 minimal cloud-image template UUID. List candidates via `upctl storage list --public --template`. |

## CI secrets generated at runtime

The workflow does **not** carry a `secrets/ci.secrets.sops.yaml` blob.
`scripts/ci-bootstrap-secrets.sh` runs in the workflow and writes a
complete synthetic secrets YAML to
`/tmp/vpn-${CI_ENV}.secrets.yaml`:

  * fresh REALITY keypair (from `ghcr.io/xtls/xray-core:<version>`
    `x25519`)
  * fresh client UUID + shortId, fresh Hysteria password, fresh
    AmneziaWG keypair + random H1..H4
  * self-signed certificate covering the CI server hostname
  * Xray + Hysteria release-asset sha256 computed live by curl +
    sha256sum from the upstream URLs

The certificate is self-signed and the geodata URLs are placeholders,
so the `pre-deploy-check` chain would reject the secrets. CI runs
with `SKIP_PRECHECK=1`; ansible's per-role validate-before-restart
still gates a broken render.

Disabled roles in CI (via `ANSIBLE_EXTRA_VARS`):

  * `enable_amneziawg=false` — kernel module + NAT not portable
  * `enable_geodata=false`   — placeholder URLs would 404
  * `enable_backup=false`    — restic-against-localhost adds noise
  * `enable_monitoring=false` — node_exporter not interesting here
  * `enable_warp_outbound=false` / `enable_honeypot=false` /
    `enable_probe_ratelimit=false` — defensive roles tested in
    their own molecule scenarios

## Cleanup invariants

The `destroy` step runs in `always()` so a half-built VPS never
outlives the job. The `cleanup CI tfvars file` step deletes the
per-run tfvars even if `destroy` failed, so the next run starts
from a clean slate. Operators verifying after a failed run should
re-check UpCloud billing once a quarter.

## What this does NOT test

  * Production traffic patterns (no real users dial the ephemeral
    REALITY endpoint).
  * Burn-check (the ephemeral IP isn't on RKN's radar long enough
    to provoke a block).
  * Long-running ASN / IP-reputation drift.

Those stay in operator-driven cadence (`make burn-check`,
`make asn-drift`, `make check-ip-reputation`).