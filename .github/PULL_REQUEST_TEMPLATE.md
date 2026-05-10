<!--
Thanks for the contribution. Most of this template is a checklist — every
item maps to a CI gate that will run on this PR. Confirming locally first
saves a CI cycle.
-->

## Summary

<!-- What does this PR change? Two-three sentences. -->

## Linked issue

<!-- Closes #NNN, or leave blank for trivial chores. -->

## Scope

- [ ] Terraform (`terraform/...`)
- [ ] Ansible role: <!-- name -->
- [ ] Ansible playbook: <!-- name -->
- [ ] Script (`scripts/...`)
- [ ] Documentation (`docs/...`, `README.md`, `CHANGELOG.md`)
- [ ] CI / GitHub automation (`.github/...`)
- [ ] Other: <!-- describe -->

## Test plan

Run before push (operator-side gates):

- [ ] `make validate` (terraform fmt + validate, gitleaks, ansible-lint, ansible syntax-check)
- [ ] `python3 scripts/check-secrets-coverage.py`
- [ ] `python3 scripts/check-templates-render.py`
- [ ] `bash -n scripts/*.sh && shellcheck -s bash -S warning scripts/*.sh`
- [ ] If a role changed: `make molecule-test ROLE=<name>`
- [ ] If transport changed: `make smoke-test` against staging

CI gates that will run automatically:

- terraform fmt+validate (matrix), cloud-init schema, ansible-lint+syntax,
  molecule (matrix), shellcheck, secrets-coverage, templates-render,
  yamllint, gitleaks, codeql, scorecard, markdown-link-check.

## Conventional Commits

This PR's commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/)
so release-please can pick them up:

- `feat: …` for new behavior
- `fix: …` for bug fixes
- `docs: …` for documentation only
- `refactor: …`, `test: …`, `perf: …`, `chore: …`

## Anything reviewers should specifically check

<!-- Edge cases, security implications, open questions. -->
