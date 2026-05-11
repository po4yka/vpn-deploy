#!/usr/bin/env bash
# Issue a one-time bootstrap token for a single client. Emits the
# sing-box JSON, encrypts under a per-token key (the token IS the key —
# random URL-safe 32 bytes), drops the payload at the bootstrap host
# via scp, and prints the URL the client should fetch.
#
# Requires:
#   subscription.enable_bootstrap = true (defaults/main.yml)
#   inventory rendered (make inventory)
#   ssh access as the admin_user
#
# Usage:
#   PROVIDER=upcloud ENV=prod scripts/issue-bootstrap.sh phone
#
# After the client fetches the URL, the payload is atomically deleted
# server-side. Subsequent fetches return 410.
set -euo pipefail

CLIENT="${1:-}"
[[ -n "$CLIENT" ]] || { echo "usage: $0 <client_name>" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"

server_ip="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"
admin_user="$(terraform -chdir="$TF_DIR" output -raw admin_user 2>/dev/null || echo admin)"
server_hostname="$(terraform -chdir="$TF_DIR" output -raw server_hostname 2>/dev/null || echo "$server_ip")"

# Use base64url for URL-safe tokens; 32 bytes → 43 chars.
token="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=' | head -c 43)"

payload="$("${REPO_ROOT}/scripts/emit-singbox.sh" "$CLIENT")"
[[ -n "$payload" ]] || { echo "empty payload from emit-singbox.sh" >&2; exit 1; }

remote_path="/var/lib/vpn-bootstrap/${token}"

# Read subscription port + bootstrap toggles from group_vars/defaults — we
# could parse the host config, but the defaults are stable and the test
# only fails if you've changed them, in which case the operator already
# knows.
sub_host="$(SOPS_FILE="${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml" \
  sops --decrypt --output-type json "${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('subscription') or {}).get('server_name') or (d.get('nginx_xhttp') or {}).get('server_name') or '')")"
[[ -n "$sub_host" ]] || sub_host="$server_hostname"
sub_port="$(SOPS_FILE="${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml" \
  sops --decrypt --output-type json "${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('subscription') or {}).get('port') or 8444)")"

printf '%s' "$payload" | ssh "${admin_user}@${server_ip}" \
  "sudo install -o vpn-bootstrap -g vpn-bootstrap -m 0600 /dev/stdin '${remote_path}'"

echo
echo "Bootstrap URL (one-time, copy to client now):"
echo "  https://${sub_host}:${sub_port}/bootstrap/${token}"
echo
echo "The token is consumed on first successful GET — second fetch returns 410."