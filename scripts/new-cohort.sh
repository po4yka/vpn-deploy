#!/usr/bin/env bash
# Add a Terraform root for a second VPS in the same provider (cohort
# pattern from RUNBOOK-add-fallback.md). Copies the existing
# `environments/<env>.tfvars` to a new ENV name, swaps `server_name` and
# (optionally) `zone`, prints next steps.
#
# Usage:
#   scripts/new-cohort.sh <new_env> [new_zone]
# Example:
#   scripts/new-cohort.sh spare de-fra1
set -euo pipefail

NEW_ENV="${1:-}"
NEW_ZONE="${2:-}"
PROVIDER="${PROVIDER:-upcloud}"
SOURCE_ENV="${SOURCE_ENV:-prod}"

if [[ -z "$NEW_ENV" ]]; then
  echo "usage: $0 <new_env> [new_zone]" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
SRC="${TF_DIR}/environments/${SOURCE_ENV}.tfvars"
DST="${TF_DIR}/environments/${NEW_ENV}.tfvars"

if [[ ! -f "$SRC" ]]; then
  echo "missing source tfvars: $SRC" >&2
  exit 1
fi
if [[ -f "$DST" ]]; then
  echo "destination already exists: $DST" >&2
  exit 1
fi

cp "$SRC" "$DST"

# Make a unique server_name
sed -i.bak -E "s/^(server_name[[:space:]]*=[[:space:]]*\")[^\"]+(\".*)/\1\2-${NEW_ENV}\2/" "$DST" || true
rm -f "${DST}.bak"
sed -i.bak -E "s/^(server_name[[:space:]]*=[[:space:]]*\")([^\"]*)\"/\1\2-${NEW_ENV}\"/" "$DST"
rm -f "${DST}.bak"

if [[ -n "$NEW_ZONE" ]]; then
  sed -i.bak -E "s/^(zone[[:space:]]*=[[:space:]]*\")[^\"]+(\".*)/\1${NEW_ZONE}\2/" "$DST"
  rm -f "${DST}.bak"
fi

cat <<EOF
created: $DST

Next steps:
  1. Edit $DST — at minimum verify server_name uniqueness, and consider a
     different storage_template or plan if needed.
  2. Provision and deploy:
       PROVIDER=${PROVIDER} ENV=${NEW_ENV} make init plan apply inventory wait
  3. Decide cohort:
       same stack as prod         → make ENV=${NEW_ENV} dry-run deploy verify
       split stack (P0 only here) → render multi-host inventory:
         HOSTS="${PROVIDER}:${SOURCE_ENV},${PROVIDER}:${NEW_ENV}" \\
         COHORTS="fullstack,p0" \\
         ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/vpn_deploy \\
         ./scripts/render-inventory.sh
         ansible-playbook ansible/playbooks/site.yml
EOF
