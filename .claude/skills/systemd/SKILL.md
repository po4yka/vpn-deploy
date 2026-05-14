---
name: systemd
description: Systemd unit conventions for vpn-deploy services (xray, hysteria, nginx, amneziawg-quick, naive, vpnd-watchdog). Hardening directives, ExecReload, journalctl recipes, drop-in overrides. Use when authoring or auditing service units in ansible/roles/**. vpn-deploy project variant — replaces the upstream Chinese SKILL.md.
---

# Systemd (vpn-deploy)

Every protocol in this repo runs as a systemd unit. Operators don't run scripts; they
`systemctl restart <unit>`. Hardening directives below are the floor — roles may tighten
but never loosen.

## Units in this repo

| Unit | Owned by role | Type | Notes |
|---|---|---|---|
| `xray.service` | `xray` | simple | P0 / P1 backend |
| `hysteria-server.service` | `hysteria` | simple | P2 UDP |
| `nginx.service` | `nginx-xhttp` (override) | forking | P1 front |
| `amneziawg-quick@<iface>.service` | `amneziawg` | oneshot RemainAfterExit | P2 device VPN |
| `naive.service` | `naive` | simple | optional cohort |
| `vpnd-watchdog.service` + `.timer` | `watchdog` | oneshot + timer | health checks |
| `backup.service` + `.timer` | `backup` | oneshot + timer | secrets export |

## Hardening floor — every service unit must include

```ini
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
```

Add `ReadWritePaths=` for the specific directories the service needs.

Network-facing services that need to bind privileged ports use:

```ini
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

AmneziaWG needs `CAP_NET_ADMIN` instead.

## Drop-in overrides

Roles add hardening via drop-ins, not by replacing the upstream unit:

```bash
# /etc/systemd/system/nginx.service.d/10-hardening.conf
[Service]
ProtectSystem=strict
ReadWritePaths=/var/log/nginx /var/lib/nginx /run
NoNewPrivileges=yes
LimitNOFILE=65535
```

```bash
ansible -m systemd -a "daemon_reload=yes name=nginx state=restarted" all
```

## Unit skeleton — simple service

```ini
[Unit]
Description=Xray Core (vpn-deploy)
Documentation=https://xtls.github.io/
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576

# Hardening floor
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/log/xray
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

## Validation

Every Ansible role that ships a unit MUST call `systemd-analyze verify` in its molecule
scenario:

```yaml
- name: verify systemd unit
  ansible.builtin.command: systemd-analyze verify {{ item }}
  loop:
    - /etc/systemd/system/xray.service
  changed_when: false
```

A failed `verify` (missing directives, bad syntax, undefined dependencies) is a CI failure.

## journalctl recipes for ops

```bash
# Tail a specific service
journalctl -u xray.service -f

# Errors since boot
journalctl -u xray.service -p err -b

# JSON for parsing
journalctl -u xray.service -o json --since "1 hour ago"

# Disk usage
journalctl --disk-usage
journalctl --vacuum-size=200M    # keep journals small on disposable nodes
```

## Don'ts

- **No `User=root`** unless the role documents *why* in its `CLAUDE.md` pitfalls section.
- **No `PrivateNetwork=yes`** on protocol-serving units (it blocks the protocol).
- **No `DynamicUser=yes`** for services that own persistent state on disk.
- **No timers without `Persistent=true`** if missed runs matter (backup, watchdog).
- **No `ExecStartPre=/bin/sh -c '...'`** with secrets in the command line — visible in
  `ps`. Use an `EnvironmentFile=` referencing a tmpfs path populated by the role.

## See also

- `ansible/roles/xray/CLAUDE.md`
- `ansible/roles/hysteria/CLAUDE.md`
- `ansible/roles/amneziawg/CLAUDE.md`
- `[[linux-hardening]]` — kernel-level companions
- `[[security-review]]` — what must not appear in `ExecStart`
