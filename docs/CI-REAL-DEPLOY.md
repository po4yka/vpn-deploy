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
| `CI_SOPS_AGE_KEY` | age private key for `secrets/ci.secrets.sops.yaml` (separate from any operator key) |
| `CI_SSH_PRIVATE_KEY` | SSH key the ephemeral VPS authorises; not reused outside CI |

Plus an inline-templated UpCloud storage template UUID. The
workflow refuses to run while the tfvars carries
`REPLACE_WITH_CI_TEMPLATE_UUID` — set this to a Debian-13 / Ubuntu-
24.04 minimal template UUID via repo settings or workflow env.

## CI-only secrets blob

A long-form follow-up: commit `secrets/ci.secrets.sops.yaml`
encrypted to `CI_SOPS_AGE_KEY` only. The blob contains synthetic
xray / hysteria / amneziawg values for a one-shot deploy. Until that
file exists, the workflow emits a warning and skips the deploy
phase (it still tests the provisioning + teardown wiring).

The CI age key MUST NOT be the operator age key. Treat the CI blob
as one-shot test data; rotate the CI age key whenever it leaves the
GitHub Actions secret store.

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