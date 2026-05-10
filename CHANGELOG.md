# Changelog

This file is managed by [release-please](https://github.com/googleapis/release-please).
Do not edit by hand — write [Conventional Commits](https://www.conventionalcommits.org/)
on `main` and the next merge of the auto-generated release PR will populate
this file.

## [1.3.0] — 2026-05-10

Initial release tracked by release-please. Repo state at this version:

- v1.0 — initial Terraform + cloud-init + Ansible scaffold (UpCloud primary,
  Hetzner/Vultr stubs, P0+P1+P2 transports, SOPS+age secrets, local TF state).
- v1.1 — watchdog role, multi-host inventory, encrypted state backups,
  Shamir-split age recovery, molecule for baseline/firewall/xray.
- v1.2 — research-grounded improvements: validate-reality-target.sh,
  smoke-test.yml, multi-host emit-singbox, restic remote sync,
  active-probing tuning, geodata role, naive role, blue-green
  orchestrator, subscription-plane v2 (revocation + rate limit).
- v1.3 — comprehensive test coverage: molecule for 9 of 12 roles,
  secrets-coverage and templates-render Python validators, shellcheck in
  CI, docs/TESTING.md.
