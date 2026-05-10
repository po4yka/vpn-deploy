#!/usr/bin/env bash
# Emit a full sing-box client JSON for one client name. Embeds every enabled
# transport profile (REALITY, XHTTP, Hysteria2, AmneziaWG) across one or
# more VPS hosts as outbounds, wired into a `selector` + `urltest` group.
#
# Single host (backwards-compatible):
#   PROVIDER=upcloud ENV=prod  scripts/emit-singbox.sh laptop
#
# Multi-host:
#   HOSTS="upcloud:prod,hetzner:prod"  scripts/emit-singbox.sh laptop
#   HOSTS="upcloud:prod,upcloud:spare" scripts/emit-singbox.sh laptop
#
# Per-host SOPS files: by default each pair uses
# ~/.config/vpn-provision/<ENV>.secrets.sops.yaml. Override with SOPS_FILE
# (single shared file) or SOPS_FILES (comma-separated, one per host).
set -euo pipefail

CLIENT_NAME="${1:-}"
if [[ -z "$CLIENT_NAME" ]]; then
  echo "usage: $0 <client_name>" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for tool in sops terraform jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Resolve host pairs
# ---------------------------------------------------------------------------
if [[ -n "${HOSTS:-}" ]]; then
  HOST_LIST="$HOSTS"
else
  HOST_LIST="${PROVIDER:-upcloud}:${ENV:-prod}"
fi
IFS=',' read -r -a host_pairs <<< "$HOST_LIST"
IFS=',' read -r -a sops_per_host <<< "${SOPS_FILES:-}"

# Each host's secrets get decrypted to its own tempfile; cleaned on exit.
WORK="$(mktemp -d -t vpn-singbox.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

OUTBOUNDS='[]'

for i in "${!host_pairs[@]}"; do
  pair="${host_pairs[$i]}"
  prov="${pair%:*}"
  env="${pair#*:}"
  tf_dir="${REPO_ROOT}/terraform/providers/${prov}"

  # Pick the right SOPS file for this host
  if [[ -n "${SOPS_FILES:-}" ]]; then
    sops_file="${sops_per_host[$i]}"
  elif [[ -n "${SOPS_FILE:-}" ]]; then
    sops_file="$SOPS_FILE"
  else
    sops_file="${HOME}/.config/vpn-provision/${env}.secrets.sops.yaml"
  fi

  if [[ ! -f "$sops_file" ]]; then
    echo "missing $sops_file (for ${prov}:${env})" >&2
    exit 1
  fi

  secrets_tmp="${WORK}/secrets-${i}.json"
  sops --decrypt --output-type json "$sops_file" > "$secrets_tmp"
  chmod 0600 "$secrets_tmp"

  server_ip="$(terraform -chdir="$tf_dir" output -raw server_ipv4)"
  server_host="$(terraform -chdir="$tf_dir" output -raw server_hostname)"
  tag_prefix="${prov}-${env}"

  client_json="$(jq --arg name "$CLIENT_NAME" '.xray.clients[]? | select(.name==$name)' "$secrets_tmp")"
  if [[ -z "$client_json" || "$client_json" == "null" ]]; then
    echo "no client named '$CLIENT_NAME' in ${sops_file} → xray.clients" >&2
    exit 1
  fi

  uuid="$(echo "$client_json" | jq -r .uuid)"
  short_id="$(echo "$client_json" | jq -r .short_id)"
  reality_pubkey="$(jq -r .xray.reality_public_key "$secrets_tmp")"
  sni="$(jq -r '.xray.server_names[0]' "$secrets_tmp")"
  xhttp_path="$(jq -r '.xray.xhttp_path // "/app-sync"' "$secrets_tmp")"
  nginx_host="$(jq -r '.nginx_xhttp.server_name // empty' "$secrets_tmp")"
  hy_pw="$(jq --arg n "$CLIENT_NAME" -r '.hysteria.clients[]? | select(.name==$n) | .password // empty' "$secrets_tmp")"
  hy_obfs_enabled="$(jq -r '.hysteria.salamander_enabled // false' "$secrets_tmp")"
  hy_obfs_pw="$(jq -r '.hysteria.salamander_password // empty' "$secrets_tmp")"

  # P0 REALITY
  OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
    --arg tag "p0-reality-${tag_prefix}" \
    --arg ip "$server_ip" --arg uuid "$uuid" \
    --arg sni "$sni" --arg pk "$reality_pubkey" --arg sid "$short_id" \
    '. += [{type:"vless", tag:$tag, server:$ip, server_port:443, uuid:$uuid,
            flow:"xtls-rprx-vision",
            tls:{enabled:true, server_name:$sni,
                 utls:{enabled:true, fingerprint:"chrome"},
                 reality:{enabled:true, public_key:$pk, short_id:$sid}}}]')"

  # P1 XHTTP via nginx (only if nginx_xhttp.server_name is in this host's secrets)
  if [[ -n "$nginx_host" ]]; then
    OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
      --arg tag "p1-xhttp-${tag_prefix}" \
      --arg ip "$server_ip" --arg host "$nginx_host" \
      --arg uuid "$uuid" --arg path "$xhttp_path" \
      '. += [{type:"vless", tag:$tag, server:$ip, server_port:443, uuid:$uuid,
              tls:{enabled:true, server_name:$host,
                   utls:{enabled:true, fingerprint:"chrome"}},
              transport:{type:"xhttp", host:$host, path:$path}}]')"
  fi

  # P2 Hysteria2
  if [[ -n "$hy_pw" && -n "$nginx_host" ]]; then
    obfs_arg=null
    if [[ "$hy_obfs_enabled" == "true" && -n "$hy_obfs_pw" ]]; then
      obfs_arg="$(jq -n --arg p "$hy_obfs_pw" '{type:"salamander", password:$p}')"
    fi
    OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
      --arg tag "p2-hysteria2-${tag_prefix}" \
      --arg ip "$server_ip" --arg host "$nginx_host" --arg pw "$hy_pw" \
      --argjson obfs "$obfs_arg" \
      '. += [{type:"hysteria2", tag:$tag, server:$ip, server_port:443,
              password:$pw, tls:{enabled:true, server_name:$host}, obfs:$obfs}
             | with_entries(select(.value != null))]')"
  fi
done

# ---------------------------------------------------------------------------
# Add selector + urltest + boilerplate
# ---------------------------------------------------------------------------
OUTBOUNDS="$(echo "$OUTBOUNDS" | jq '
  . + [
    {type:"selector", tag:"select",
     outbounds: ([.[].tag] + ["auto"]),
     default:"auto", interrupt_exist_connections:false},
    {type:"urltest",  tag:"auto",
     outbounds:[.[].tag],
     url:"https://www.gstatic.com/generate_204",
     interval:"5m", tolerance:50},
    {type:"direct", tag:"direct"},
    {type:"block",  tag:"block"},
    {type:"dns",    tag:"dns-out"}
  ]')"

jq -n \
  --arg client "$CLIENT_NAME" \
  --argjson outbounds "$OUTBOUNDS" \
  '{
    "log": {"level":"warn", "timestamp":true},
    "dns": {
      "servers": [
        {"tag":"remote", "address":"https://1.1.1.1/dns-query", "detour":"select"},
        {"tag":"local",  "address":"local",                       "detour":"direct"}
      ],
      "rules": [{"outbound":["any"], "server":"local"}]
    },
    "inbounds": [{
      "type":"tun", "tag":"tun-in",
      "interface_name":"tun0",
      "inet4_address":"172.19.0.1/30",
      "auto_route":true, "strict_route":true,
      "stack":"system", "sniff":true
    }],
    "outbounds": $outbounds,
    "route": {
      "rules": [
        {"protocol":"dns", "outbound":"dns-out"},
        {"ip_is_private":true, "outbound":"direct"}
      ],
      "final":"select",
      "auto_detect_interface":true
    }
  }'
