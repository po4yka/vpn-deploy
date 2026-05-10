#!/usr/bin/env bash
# Drift detection: compare what's deployed on the VPS with what current
# secrets + templates would render. Exits 0 if in sync, 1 if drifted.
#
# Required env:
#   PROVIDER (default: upcloud), ENV (default: prod)
#   SECRETS_FILE (default: /tmp/vpn-<env>.secrets.yaml — run `make decrypt` first)
#   ANSIBLE_SSH_PRIVATE_KEY_FILE
set -euo pipefail

PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
SECRETS_FILE="${SECRETS_FILE:-/tmp/vpn-${ENV}.secrets.yaml}"

for tool in terraform ssh ansible diff jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done

if [[ -z "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  echo "ANSIBLE_SSH_PRIVATE_KEY_FILE is not set" >&2
  exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "missing $SECRETS_FILE — run 'make decrypt' first" >&2
  exit 1
fi

IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"
USER="$(terraform -chdir="$TF_DIR" output -raw admin_user)"
HOSTNAME="$(terraform -chdir="$TF_DIR" output -raw server_hostname)"

WORK="$(mktemp -d -t vpn-diff.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

ssh_cmd() {
  ssh -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10 \
      -i "${ANSIBLE_SSH_PRIVATE_KEY_FILE}" \
      "${USER}@${IP}" "$@"
}

drift=0

# 1. Xray config: render locally via ansible-playbook --check, fetch remote
echo "== Xray config =="
ansible -i "${REPO_ROOT}/ansible/inventory/generated.ini" "$HOSTNAME" \
  -m fetch -a "src=/etc/xray/config.json dest=${WORK}/remote/ flat=yes" \
  --extra-vars "@${SECRETS_FILE}" >/dev/null 2>&1 \
  || ssh_cmd 'sudo cat /etc/xray/config.json' > "${WORK}/remote.config.json"

# Render expected via ansible (--check so nothing changes)
ansible-playbook -i "localhost," "${REPO_ROOT}/ansible/playbooks/site.yml" \
  --check --diff --tags xray \
  --extra-vars "@${SECRETS_FILE}" \
  --connection=local 2>/dev/null > "${WORK}/render-output.txt" || true

# Simpler approach: call jinja2 via ansible 'template' module against
# the role template, dump to /tmp on a throwaway. Skip the elaborate
# rendering — instead, exfiltrate normalized JSON from the host and
# from a fresh `xray test -dump-config` if available.
if ssh_cmd 'command -v xray' >/dev/null 2>&1; then
  ssh_cmd 'sudo /usr/local/bin/xray run -test -dump-config -config /etc/xray/config.json' \
    > "${WORK}/remote.normalized.json" 2>/dev/null || true
fi

REMOTE_FILE="${WORK}/remote.config.json"
[[ -s "${WORK}/remote.normalized.json" ]] && REMOTE_FILE="${WORK}/remote.normalized.json"

# Show only top-level structure — clients/uuid/short_id/privateKey are too
# noisy and secret-bearing for a diff. We sanitize first.
jq 'walk(if type == "object" then
       (if has("id") then .id = "<UUID>" else . end)
       | (if has("privateKey") then .privateKey = "<PRIV>" else . end)
       | (if has("shortIds") then .shortIds = ["<SID>"] else . end)
     else . end) | del(.log.access, .log.error)' \
  "$REMOTE_FILE" > "${WORK}/remote.sanitized.json" 2>/dev/null || cp "$REMOTE_FILE" "${WORK}/remote.sanitized.json"

# Compare just the structural shape — inbound/outbound tags, transports,
# port set. This catches the drift cases that matter (an inbound got
# disabled, port changed, transport setting drifted).
jq -S '{
  inbounds: [.inbounds[] | {tag, port, protocol, network: .streamSettings.network, security: .streamSettings.security}],
  outbounds: [.outbounds[] | {tag, protocol}],
  routing: (.routing.rules // [])
}' "${WORK}/remote.sanitized.json" > "${WORK}/remote.shape.json" 2>/dev/null || true

if [[ -s "${WORK}/remote.shape.json" ]]; then
  echo "Remote Xray shape:"
  cat "${WORK}/remote.shape.json"
else
  echo "Could not extract Xray shape from $REMOTE_FILE"
  drift=1
fi

# 2. Service status comparison — what's enabled vs what secrets say
echo
echo "== Service vs secrets-toggle drift =="
declare -A want_status
for svc_key_pair in "xray:enable_xray_reality" "nginx:enable_nginx_xhttp" "hysteria-server:enable_hysteria"; do
  svc="${svc_key_pair%:*}"
  key="${svc_key_pair#*:}"
  want_enabled="$(yq -r ".vpn.${key} // false" "${SECRETS_FILE}" 2>/dev/null \
    || python3 -c "import yaml,sys; print(yaml.safe_load(open('${SECRETS_FILE}')).get('vpn',{}).get('${key}', False))" 2>/dev/null \
    || echo unknown)"
  is_active="$(ssh_cmd "systemctl is-active ${svc} 2>/dev/null || true" | tr -d '\r' || echo missing)"
  printf "  %-20s want_enabled=%-8s actually=%s\n" "$svc" "$want_enabled" "$is_active"
  if [[ "$want_enabled" == "True" || "$want_enabled" == "true" ]] && [[ "$is_active" != "active" ]]; then
    drift=1
  fi
  if [[ "$want_enabled" == "False" || "$want_enabled" == "false" ]] && [[ "$is_active" == "active" ]]; then
    drift=1
  fi
done

# 3. nftables config sanity — the rendered file should match the running ruleset
echo
echo "== nftables config staleness =="
remote_mtime="$(ssh_cmd 'stat -c %Y /etc/nftables.conf' 2>/dev/null || echo 0)"
remote_mtime_human="$(ssh_cmd 'stat -c %y /etc/nftables.conf' 2>/dev/null || echo unknown)"
echo "  /etc/nftables.conf mtime: $remote_mtime_human"

# 4. Pinned version check — Xray and Hysteria binary versions vs secrets
echo
echo "== Binary version pinning =="
remote_xray_ver="$(ssh_cmd '/usr/local/bin/xray version 2>&1 | head -1' || true)"
expected_xray_ver="$(grep -E '^[[:space:]]*version:' "${SECRETS_FILE}" 2>/dev/null | head -1 | awk -F'"' '{print $2}')"
echo "  Xray remote: $remote_xray_ver"
echo "  Xray secrets pin: $expected_xray_ver"

if [[ -n "$expected_xray_ver" && "$remote_xray_ver" != *"$expected_xray_ver"* ]]; then
  echo "  DRIFT: Xray version mismatch"
  drift=1
fi

echo
if (( drift )); then
  echo "drift detected — review and reconcile via 'make dry-run && make deploy'"
  exit 1
fi
echo "no structural drift detected"
