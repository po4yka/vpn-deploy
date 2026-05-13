# role: baseline — every host starts here

## Design decisions

**Sets ground state, not policy** — installs sysctl baseline, time sync,
journald limits, unattended-upgrades for security-only patches, fail2ban
defaults. Doesn't open ports; doesn't install Xray/nginx. Other roles
layer on top.

**No reboots from this role** — package upgrades that need a reboot are
flagged via the `reboot_required` fact and surfaced at the end of `verify.yml`.
A reboot mid-deploy would burn idempotency.

## What's done well

- **Single source for sysctl** — `templates/99-meridian-sysctl.conf.j2`
  consolidates kernel tunables (`net.ipv4.tcp_fastopen`, `tcp_bbr`, etc).
  Loaded with priority 99 so cloud-init defaults can't override.
- **Time sync hard-required** — REALITY breaks if clocks drift > 90s. The
  role installs and enables `chrony` and `verify.yml` asserts sync state.

## Pitfalls

- **`unattended-upgrades` and pinned-package conflict** — Xray binary is
  hash-pinned per `docs/XRAY-RELEASE-LINE.md`; baseline must blacklist Xray
  from auto-upgrades or `apt-get` will swap the binary out from under us.
- **Hostname change requires re-running cloud-init handlers** — don't
  change `ansible_hostname` mid-deploy.
- **`PasswordAuthentication no` is set by cloud-init *first*** — baseline
  doesn't re-set it. If you ever rip out cloud-init, this assumption breaks
  silently (the SSH connection survives because keys still work; the
  password path is suddenly open).
