# Enabling release-please

The `release-please` workflow is gated behind two prerequisites the
workflow itself can't toggle. Until both are configured the job stays
**skipped** — green run summary, no PR creation.

## Step 1 — allow GitHub Actions to create PRs

Repo → **Settings → Actions → General → Workflow permissions** →

- Tick **"Allow GitHub Actions to create and approve pull requests"**.

This is a per-repo setting (and a parallel org-level setting if your
account is an org). Without it, the action exits with:

```
release-please failed: GitHub Actions is not permitted to create or
approve pull requests.
```

## Step 2 — set the repo variable

Repo → **Settings → Secrets and variables → Actions → Variables** →
**New repository variable**:

- Name: `RELEASE_PLEASE_ENABLED`
- Value: `true`

The workflow's `if: ${{ vars.RELEASE_PLEASE_ENABLED == 'true' }}` gate
flips from "skipped" to "running" the next time `main` is pushed.

## Step 3 — verify

After the next conventional-commit merge to `main`:

1. Open Actions → release-please run → check the job ran (not
   skipped).
2. Open Pull requests — release-please should have opened a release
   PR titled `chore(release): vpn-deploy x.y.z` listing the
   conventional commits since the last release.
3. Merging that PR creates a tag and a GitHub Release; CHANGELOG.md
   gets the entries.

## What if I want to disable it again

Set `RELEASE_PLEASE_ENABLED=false` (or delete the variable). The job
goes back to "skipped" without removing the workflow file or losing
the manifest history.

## Why this is gated

The workflow is in the repo by default so operators who care about
auto-changelog get it for free. But release-please can't be silently
enabled — it needs the operator to make a deliberate choice (PR
creation is a real privilege; auto-PR bots are a known supply-chain
attack vector). The variable gate forces explicit opt-in.
