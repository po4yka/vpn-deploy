#!/usr/bin/env bash
# Render Ansible inventory from Terraform outputs. Supports single-host
# (backwards-compatible) and multi-host modes.
#
# Single host (default):
#   PROVIDER=upcloud ENV=prod ./scripts/render-inventory.sh
#
# Multi-host: pass a comma-separated PROVIDER:ENV list. Each pair must point
# to a Terraform root with valid state.
#   HOSTS="upcloud:prod,hetzner:prod" ./scripts/render-inventory.sh
#
# Cohort assignment: optional COHORTS env, comma-separated, one per host. The
# host gets added to a [vpn-<cohort>] group.
#   HOSTS="upcloud:prod,hetzner:prod" COHORTS="p0,p1p2" ./scripts/render-inventory.sh
#
# Required env: ANSIBLE_SSH_PRIVATE_KEY_FILE.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO_ROOT}/ansible/inventory/generated.ini"

if [[ -z "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  echo "ANSIBLE_SSH_PRIVATE_KEY_FILE is not set" >&2
  exit 1
fi

if [[ -n "${HOSTS:-}" ]]; then
  HOST_LIST="$HOSTS"
else
  HOST_LIST="${PROVIDER:-upcloud}:${ENV:-prod}"
fi

IFS=',' read -r -a host_pairs <<< "$HOST_LIST"
IFS=',' read -r -a cohort_list <<< "${COHORTS:-}"

if [[ -n "${COHORTS:-}" && ${#cohort_list[@]} -ne ${#host_pairs[@]} ]]; then
  echo "COHORTS count (${#cohort_list[@]}) must equal HOSTS count (${#host_pairs[@]})" >&2
  exit 1
fi

declare -a vpn_lines=()
declare -A cohort_groups=()

for i in "${!host_pairs[@]}"; do
  pair="${host_pairs[$i]}"
  prov="${pair%:*}"
  env="${pair#*:}"
  tf_dir="${REPO_ROOT}/terraform/providers/${prov}"

  if [[ ! -d "$tf_dir" ]]; then
    echo "no terraform root for provider '${prov}'" >&2
    exit 1
  fi

  ip="$(terraform -chdir="$tf_dir" output -raw server_ipv4)"
  user="$(terraform -chdir="$tf_dir" output -raw admin_user)"
  hostname="$(terraform -chdir="$tf_dir" output -raw server_hostname)"

  vpn_lines+=("${hostname} ansible_host=${ip} ansible_user=${user} provider=${prov} env=${env}")

  if [[ -n "${cohort_list[$i]:-}" ]]; then
    cohort="${cohort_list[$i]}"
    cohort_groups["$cohort"]="${cohort_groups[$cohort]:-}${hostname}"$'\n'
  fi
done

{
  echo "[vpn]"
  printf '%s\n' "${vpn_lines[@]}"
  echo
  for cohort in "${!cohort_groups[@]}"; do
    echo "[vpn-${cohort}]"
    printf '%s' "${cohort_groups[$cohort]}"
    echo
  done
  echo "[vpn:vars]"
  echo "ansible_ssh_private_key_file=${ANSIBLE_SSH_PRIVATE_KEY_FILE}"
  echo "ansible_python_interpreter=/usr/bin/python3"
} > "$OUT"

echo "wrote $OUT"
echo "--"
cat "$OUT"
