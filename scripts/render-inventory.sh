#!/usr/bin/env bash
# Render Ansible inventory from Terraform outputs.
#
# Required env: PROVIDER (default: upcloud), ENV (default: prod),
#               ANSIBLE_SSH_PRIVATE_KEY_FILE
set -euo pipefail

PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
OUT="${REPO_ROOT}/ansible/inventory/generated.ini"

if [[ ! -d "$TF_DIR" ]]; then
  echo "no such terraform root: $TF_DIR" >&2
  exit 1
fi

if [[ -z "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  echo "ANSIBLE_SSH_PRIVATE_KEY_FILE is not set" >&2
  exit 1
fi

IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"
USER="$(terraform -chdir="$TF_DIR" output -raw admin_user)"
HOSTNAME="$(terraform -chdir="$TF_DIR" output -raw server_hostname)"

cat > "$OUT" <<EOF
[vpn]
${HOSTNAME} ansible_host=${IP} ansible_user=${USER}

[vpn:vars]
ansible_ssh_private_key_file=${ANSIBLE_SSH_PRIVATE_KEY_FILE}
ansible_python_interpreter=/usr/bin/python3
EOF

echo "wrote $OUT"
echo "--"
cat "$OUT"
