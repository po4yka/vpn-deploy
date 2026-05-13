# role: backup — restic to age-encrypted remote

## Design decisions

**restic + age + remote object store** — restic's repo is age-encrypted before
upload. The age key is the same one that decrypts SOPS — single recovery key,
Shamir-split per `docs/AGE-RECOVERY.md`.

**Server only backs up its own state** — `/etc/xray`, `/etc/nginx`,
`/var/lib/<service>/` configs and small data. Not logs (`monitoring` has
retention).

## What's done well

- **Pre-restore validation** — `RUNBOOK-restore.md` requires checksum
  verification before any restore touches `/etc/`. The role's restore
  playbook refuses to overwrite if the target file's hash matches the backup
  (idempotent restore).
- **Daily by default; manual trigger via `scripts/`** — no surprise weekend
  backup storms.

## Pitfalls

- **age key recoverability is the whole game** — lose all Shamir shares and
  the backups are paperweights. Test recovery quarterly per the runbook.
- **restic forget policy is destructive** — keep at least 7 daily + 4 weekly.
  Bumping the policy down between deploys silently aged-out older snapshots.
- **Remote store credentials live in SOPS** — never in env on the server.
- **Backup runs as a separate systemd user** — don't grant it write to the
  config dirs; restore is operator-initiated, not service-initiated.
