# Testing — what's covered and what isn't

The repo's defense-in-depth philosophy applies to its own correctness: every
config, role, and script is checked at multiple layers before it can hit a
real VPS. This doc enumerates each layer and where coverage gaps exist
(with explicit reasons).

## Coverage matrix

| Artifact | Static check | Render check | Functional test (molecule) | Notes |
|---|---|---|---|---|
| **Terraform — UpCloud** | `terraform fmt -check` + `terraform validate` (CI) | n/a | n/a | CI matrix runs all three providers. |
| **Terraform — Hetzner / Vultr** | `terraform fmt -check` + `terraform validate` (CI) | n/a | n/a | Provider roots mirror the inventory-facing UpCloud outputs. |
| **cloud-init template** | `cloud-init schema --config-file` (CI) | rendered via Terraform `console` | n/a | |
| **Ansible playbooks** | `ansible-lint` + `ansible-playbook --syntax-check` (CI) | n/a | n/a | site.yml asserts VPN_SECRETS_FILE is set; CI passes the example schema as a stub. |
| **Ansible role: baseline** | ansible-lint | render check | **molecule** (debian13 + ubuntu24.04) | tests sshd hardening, sysctl, timesync, IPv4 forwarding gating. |
| **Ansible role: firewall** | ansible-lint | render check | **molecule** | tests nftables.conf parse + presence of expected ports. |
| **Ansible role: xray** | ansible-lint | render check (JSON validity) | **molecule** (template-only, stub binary) | tests config.json shape, systemd unit, symlink rollback. |
| **Ansible role: nginx-xhttp** | ansible-lint | render check (`nginx -t`) | **molecule** (idempotence + verify) | self-signed cert generated in pre_tasks; verifies no Cloudflare-specific directives leaked into RU baseline. |
| **Ansible role: hysteria** | ansible-lint | render check | **molecule** (template-only, stub binary) | verifies clients render + Salamander disabled by default. |
| **Ansible role: amneziawg** | ansible-lint | render check | **molecule (syntax+create only)** | full converge needs a kernel TUN device + golang build of amneziawg-go that Docker can't reliably provide; scenario exercises task-file structure so regressions are caught early, deeper testing happens against a real VPS. |
| **Ansible role: monitoring** | ansible-lint | render check | **molecule** | verifies node_exporter + journald + logrotate. |
| **Ansible role: watchdog** | ansible-lint + `bash -n` (verify play) | render check | **molecule** + idempotence | verifies probe script syntax + env file perms + topic rendering. |
| **Ansible role: backup** | ansible-lint | render check | **molecule** | verifies restic init + remote-sync block correctly *omitted* when disabled. |
| **Ansible role: subscription-host** | ansible-lint | render check (`nginx -t`) | **molecule** + idempotence | verifies revoked-tokens map + rate-limit zone + payload dir perms. |
| **Ansible role: geodata** | ansible-lint | render check | **molecule (syntax-only sequence)** | converge would couple to upstream URL availability + rate limits; scenario still exercises task-file structure. Use `molecule converge` manually for ad-hoc full-path testing. |
| **Ansible role: naive** | ansible-lint | render check (Caddyfile syntax NOT validated — Caddy not in CI matrix) | **molecule (syntax-only sequence)** | xcaddy from-source build skipped in CI to avoid Go-module-network flakiness; `molecule converge` runs it locally. |
| **Ansible role: honeypot** | ansible-lint | render check | **molecule** + idempotence | verifies service active, listener bound to configured port, script installed. |
| **Ansible role: probe-ratelimit** | ansible-lint | render check | **molecule** + idempotence | verifies daemon script + systemd unit + active state. nftables `probe_offenders` set is exercised in the full-stack scenario. |
| **Ansible role: warp-outbound** | ansible-lint | render check | **molecule (syntax-only sequence)** | Cloudflare WARP installer expects systemd-networkd + a registerable endpoint not available in CI; structure validation only. |
| **Full stack** | ansible-lint | render check | **molecule (full-stack scenario)** | runs the entire `site.yml` end-to-end inside a privileged Debian-13 container with NET_ADMIN; verifies every enabled service is up + listening. See `ansible/molecule/full-stack/`. |
| **Shell scripts (16)** | `bash -n` syntax + **`shellcheck -s bash -S warning`** (CI) | n/a | n/a | every script in `scripts/` runs through shellcheck. |
| **Python validators** | implicit — they validate everything else | n/a | n/a | |
| **Secrets schema** | **`scripts/check-secrets-coverage.py`** | n/a | n/a | Walks every Jinja2 template, ensures every top-level variable is declared in `secrets/prod.secrets.example.yaml`, `group_vars/all.yml`, or a role's `defaults/main.yml`. |
| **Jinja2 templates (20)** | **`scripts/check-templates-render.py`** | renders all 20 against synthetic + example data | n/a | Catches Jinja syntax errors, JSON-invalid output for `*.json.j2`, nginx parse errors for site configs. |
| **Cohort group_vars** | render check (group_vars/all.yml + cohort file are merged into render env) | n/a | n/a | If a cohort file references a flag the role doesn't accept, render fails. |
| **YAML formatting** | **yamllint** (CI) | n/a | n/a | uses `.yamllint.yml` profile. |
| **Secret leak detection** | **gitleaks** with custom rules (CI + pre-commit) | n/a | n/a | Custom rules: VLESS/Trojan/Hysteria URIs, REALITY priv keys, WG priv keys, age-secret-key, subscription tokens. |
| **Placeholder leak** | **`scripts/pre-commit-placeholder-scan.py`** (pre-commit) | n/a | n/a | Rejects any staged file (outside the schema example + generator scripts) that carries a `REPLACE_WITH_*` token. |
| **Decrypted-secrets audit** | **`scripts/spot-check-secrets.py`** (gating `make deploy`/`verify`) | walks the decrypted YAML | n/a | Placeholder check, cert expiry, RSA modulus match, H1..H4 type, password length. Bypass with `SKIP_PRECHECK=1`. |
| **Cert hygiene** | **`scripts/check-certs.sh`** (gating `make deploy`/`verify`) | openssl-driven | n/a | SAN coverage, expiry < 14 days, self-signed detection, modulus match across nginx_xhttp / hysteria / naive. |
| **Pinned-binary reproducibility** | **`.github/workflows/reproducible-build.yml`** (CI) | go build + sha256 compare | n/a | Three jobs: xray (from-source rebuild → soft-warn on bytewise drift), hysteria (hard-fail on release-asset sha256 mismatch), RealiTLScanner (same). |
| **Real-VPS end-to-end** | **`.github/workflows/real-vps-deploy.yml`** (workflow_dispatch / `ci-real-deploy` label) | provision → site.yml → verify → smoke-test → destroy | n/a | Approximates production deploy as closely as Actions allows. Ephemeral UpCloud VPS per run. See `docs/CI-REAL-DEPLOY.md`. |
| **Kill-switch validation** | **`scripts/check-singbox-killswitch.py`** (operator-driven) | static JSON analysis | n/a | Verifies auto_route + strict_route, route.final ≠ direct, DNS detour ≠ direct, no IPv6-only outbounds. |

## Test phases mapped to operator workflow

| Operator step | Tests that protect it |
|---|---|
| `git commit` (local) | pre-commit hooks: gitleaks, terraform fmt, ansible-lint, yamllint, **shellcheck**, **secrets-coverage**, **templates-render**, **placeholder-scan** |
| `git push` (PR) | CI matrix: terraform fmt+validate (3 providers), cloud-init schema, ansible-lint + syntax, **all 15 role + 1 full-stack molecule scenarios**, **reproducible-build** (xray + hysteria + RealiTLScanner sha256), shellcheck, secrets-coverage, templates-render, yamllint, gitleaks |
| PR labeled `ci-real-deploy` | **real-vps-deploy** workflow: provisions an ephemeral UpCloud VPS, runs site.yml + verify + smoke-test, destroys — closest approximation to production in CI. See `docs/CI-REAL-DEPLOY.md`. |
| `make validate` (operator) | terraform fmt + validate + gitleaks + ansible-lint + ansible syntax-check |
| `make validate-target` | live probe of REALITY target (TLS / H2 / SAN / uTLS / ASN / template OPSEC) |
| `make plan` | terraform plan (catches infrastructure drift) |
| `make dry-run` / `make deploy` / `make verify` | **pre-deploy-check** runs first: spot-check-secrets + check-certs; bypass with `SKIP_PRECHECK=1` |
| `make deploy` | role handlers run validate-before-restart (Xray, nftables, nginx) |
| `make verify [TAG_ON_SUCCESS=1]` | post-deploy gates assert services up, listeners present; optionally git-tag the commit as `vpn-deploy-known-good-*` |
| `make drift-since-tag` | weekly: diff fleet against the last known-good tag (terraform plan + ansible --check) |
| `make smoke-test` | end-to-end real-traffic dial through every enabled profile |
| `make check-killswitch BUNDLE=…` | per-client validation of emitted sing-box bundle (5 rules: auto_route, strict_route, sniff, final ≠ direct, DNS detour ≠ direct, no IPv6-only outbound) |

## Dependency updates

Pinned versions are not maintained by hand — Dependabot opens weekly PRs
for the ecosystems it supports, and each PR runs through the full CI
matrix above before a human merges.

| Ecosystem | Dependabot covers? | Where pinned | Refresh cadence |
|---|---|---|---|
| GitHub Actions | yes | `.github/workflows/*.yml` | weekly (Mon 09:00 UTC, grouped) |
| Terraform providers | yes | `terraform/providers/*/versions.tf` + `.terraform.lock.hcl` | weekly per provider directory |
| Python tooling | yes | `requirements.txt` | weekly, grouped (ansible-core / ansible-lint / molecule / yamllint / jmespath) |
| Ansible Galaxy collections | **no** | exact versions in `requirements.yml` | manual quarterly review (see below) |
| Xray / Hysteria binaries | n/a (runtime only) | `secrets/prod.secrets.example.yaml` schema documents version + sha256 fields | operator decides per release; see `docs/RUNBOOK-rotate.md` |
| geodata (geosite/geoip) | n/a | concrete URLs + sha256 values in the deployed vars file | daily systemd timer on the VPS via `geodata` role |

### Manual quarterly Galaxy collection refresh

Dependabot does not yet support Ansible Galaxy. Once a quarter, run:

```bash
# Inspect current pins
grep -A1 'name:' requirements.yml

# Check upstream for newer versions
ansible-galaxy collection list  # local cache
# or browse https://galaxy.ansible.com/<collection>

# Bump exact pins in requirements.yml; install fresh
rm -rf ~/.ansible/collections
ansible-galaxy collection install -r requirements.yml --force

# Re-run molecule on at least one role
make molecule-test ROLE=baseline

# Commit with: chore(deps): refresh Ansible Galaxy collections
```

Auto-merge is intentionally **not** enabled for any Dependabot PR — every
update goes through a human review. Operators who want auto-merge can
configure it per-ecosystem in repo Settings.

## What is intentionally NOT tested

- **Live external network reachability of upstream geodata / Xray / Hysteria
  binaries.** Test would couple the build to upstream availability. We
  pin-and-checksum at deploy; CI doesn't re-validate every release.
- **AmneziaWG userspace build inside Docker.** Requires kernel TUN; would
  need a privileged runner. Render check covers template correctness;
  `awg show` is part of `verify.yml` against a real VPS.
- **NaiveProxy xcaddy build.** Pulls Go modules; flaky in CI. Render check
  + bash-syntax cover the artifact shape; the build itself runs only on
  the target VPS during deploy.
- **End-to-end traffic against geographic locations** (RU, EU, US). Would
  require live infrastructure with the right BGP. This is what
  `make burn-check` (operator-side cron) covers post-deploy.
- **Long-running stability** (memory leaks, descriptor exhaustion). Out of
  scope for unit-level testing; the watchdog role catches it post-deploy.
- **Active-probing simulation** against the deployed REALITY listener. The
  validator covers the static OPSEC properties; behavior under real
  probing is observable only against live infrastructure.

## Adding a new role

When you add a role, the checklist is:

1. Write the role under `ansible/roles/<name>/`.
2. Reference it in `ansible/playbooks/site.yml` with a `vpn.enable_<name>`
   toggle.
3. Add the toggle to `ansible/group_vars/all.yml` and to every
   `vpn-<cohort>.yml`.
4. If the role consumes new secret keys, add them to
   `secrets/prod.secrets.example.yaml`. **Do not skip this.** The
   `check-secrets-coverage.py` validator will fail PRs that miss it.
5. Either:
   - Add `ansible/roles/<name>/molecule/default/{molecule,converge,verify}.yml`
     and add the role to the molecule matrix in `.github/workflows/ci.yml`, or
   - Document a justified skip in this file's coverage matrix.
6. If the role drops shell scripts via templates, the rendered output must
   pass `bash -n` (added to your verify play).

## Adding a new template

1. Reference variables that exist in role defaults, group_vars, or the
   secrets schema. The `check-secrets-coverage.py` validator will catch
   omissions.
2. If it's a `*.json.j2` template, the render check will validate it as
   JSON.
3. If it's an nginx site config, name it `*.conf.j2` under a role whose
   parent dir contains "nginx" — the render check will run `nginx -t`.

## Adding a new script

1. `bash -n` must pass (catches syntax).
2. `shellcheck -s bash -S warning` must pass (catches common bash
   pitfalls). Add `# shellcheck disable=SCXXXX  # reason` for justified
   exceptions.
3. Include a top-of-file comment block describing usage, env, and exit
   codes.
