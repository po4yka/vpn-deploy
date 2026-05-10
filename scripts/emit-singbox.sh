#!/usr/bin/env bash
# Emit a full sing-box client JSON for one client name. Embeds every enabled
# transport profile (REALITY, XHTTP, Hysteria2, AmneziaWG) as outbounds and
# wires a `selector` + `urltest` group so the client can fail over without
# operator intervention.
#
# Usage:
#   scripts/emit-singbox.sh <client_name> [> client.json]
#
# Reads:
#   - SOPS-encrypted secrets (auto-decrypts via `sops`)
#   - terraform/providers/<PROVIDER>/ outputs for server IPv4
#   - terraform/providers/<PROVIDER>/environments/<ENV>.tfvars for server hostname
#
# Required env:
#   PROVIDER (default: upcloud)
#   ENV      (default: prod)
#   SOPS_FILE (default: ~/.config/vpn-provision/<ENV>.secrets.sops.yaml)
set -euo pipefail

CLIENT_NAME="${1:-}"
if [[ -z "$CLIENT_NAME" ]]; then
  echo "usage: $0 <client_name>" >&2
  exit 1
fi

PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"
SOPS_FILE="${SOPS_FILE:-${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"

for tool in sops terraform jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "missing $SOPS_FILE" >&2
  exit 1
fi

SERVER_IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"
SERVER_HOST="$(terraform -chdir="$TF_DIR" output -raw server_hostname)"

# Decrypt to a tmpfile with mode 0600; clean up on exit
SECRETS_TMP="$(mktemp -t vpn-singbox-secrets.XXXXXX)"
chmod 0600 "$SECRETS_TMP"
trap 'shred -u "$SECRETS_TMP" 2>/dev/null || rm -f "$SECRETS_TMP"' EXIT
sops --decrypt --output-type json "$SOPS_FILE" > "$SECRETS_TMP"

CLIENT_JSON="$(jq --arg name "$CLIENT_NAME" '.xray.clients[] | select(.name==$name)' "$SECRETS_TMP")"
if [[ -z "$CLIENT_JSON" || "$CLIENT_JSON" == "null" ]]; then
  echo "no client named '$CLIENT_NAME' in xray.clients" >&2
  exit 1
fi
UUID="$(echo "$CLIENT_JSON" | jq -r .uuid)"
SHORT_ID="$(echo "$CLIENT_JSON" | jq -r .short_id)"

REALITY_PUBKEY="$(jq -r .xray.reality_public_key "$SECRETS_TMP")"
SNI="$(jq -r '.xray.server_names[0]' "$SECRETS_TMP")"
XHTTP_PATH="$(jq -r '.xray.xhttp_path // "/app-sync"' "$SECRETS_TMP")"
NGINX_HOST="$(jq -r '.nginx_xhttp.server_name // empty' "$SECRETS_TMP")"

HY_PASSWORD="$(jq --arg name "$CLIENT_NAME" -r '.hysteria.clients[] | select(.name==$name) | .password // empty' "$SECRETS_TMP")"
HY_HOST="$NGINX_HOST"
HY_SALAMANDER_ENABLED="$(jq -r '.hysteria.salamander_enabled // false' "$SECRETS_TMP")"
HY_SALAMANDER_PASSWORD="$(jq -r '.hysteria.salamander_password // empty' "$SECRETS_TMP")"

AWG_LISTEN_PORT="$(jq -r '.amneziawg.listen_port // 51820' "$SECRETS_TMP" 2>/dev/null || echo 51820)"

# Build outbounds[] array dynamically
OUTBOUNDS='[]'

# REALITY (always present in v1 if a client matches)
OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
  --arg ip "$SERVER_IP" \
  --arg uuid "$UUID" \
  --arg sni "$SNI" \
  --arg pubkey "$REALITY_PUBKEY" \
  --arg sid "$SHORT_ID" \
  '. += [{
     "type": "vless",
     "tag": "p0-reality",
     "server": $ip,
     "server_port": 443,
     "uuid": $uuid,
     "flow": "xtls-rprx-vision",
     "tls": {
       "enabled": true,
       "server_name": $sni,
       "utls": { "enabled": true, "fingerprint": "chrome" },
       "reality": { "enabled": true, "public_key": $pubkey, "short_id": $sid }
     }
   }]')"

# XHTTP via nginx (P1) — only if nginx_xhttp.server_name is set
if [[ -n "$NGINX_HOST" ]]; then
  OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
    --arg ip "$SERVER_IP" \
    --arg host "$NGINX_HOST" \
    --arg uuid "$UUID" \
    --arg path "$XHTTP_PATH" \
    '. += [{
       "type": "vless",
       "tag": "p1-xhttp",
       "server": $ip,
       "server_port": 443,
       "uuid": $uuid,
       "tls": {
         "enabled": true,
         "server_name": $host,
         "utls": { "enabled": true, "fingerprint": "chrome" }
       },
       "transport": {
         "type": "xhttp",
         "host": $host,
         "path": $path
       }
     }]')"
fi

# Hysteria2 (P2 UDP) — only if password and host present
if [[ -n "$HY_PASSWORD" && -n "$HY_HOST" ]]; then
  HY_OBFS='null'
  if [[ "$HY_SALAMANDER_ENABLED" == "true" && -n "$HY_SALAMANDER_PASSWORD" ]]; then
    HY_OBFS="$(jq -n --arg p "$HY_SALAMANDER_PASSWORD" '{"type":"salamander","password":$p}')"
  fi
  OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
    --arg ip "$SERVER_IP" \
    --arg host "$HY_HOST" \
    --arg pw "$HY_PASSWORD" \
    --argjson obfs "$HY_OBFS" \
    '. += [{
       "type": "hysteria2",
       "tag": "p2-hysteria2",
       "server": $ip,
       "server_port": 443,
       "password": $pw,
       "tls": { "enabled": true, "server_name": $host },
       "obfs": $obfs
     } | with_entries(select(.value != null))]')"
fi

# AmneziaWG (P2 device-VPN) — clients usually want a separate config file,
# not a sing-box outbound. We still emit it as a `wireguard` outbound so the
# JSON is complete; sing-box ≥1.10 supports WG outbounds. Operator can strip
# it if their client expects a .conf file instead.
AWG_PEER="$(jq --arg name "$CLIENT_NAME" '.amneziawg_secrets.peers[] | select(.name==$name)' "$SECRETS_TMP" 2>/dev/null || echo null)"
if [[ -n "$AWG_PEER" && "$AWG_PEER" != "null" ]]; then
  AWG_PSK="$(echo "$AWG_PEER" | jq -r .preshared_key)"
  AWG_ALLOWED_IPS="$(echo "$AWG_PEER" | jq -r '.allowed_ips // "10.66.66.2/32"')"
  AWG_SERVER_PUBKEY="$(jq -r '.amneziawg_secrets.server_public_key // ""' "$SECRETS_TMP")"
  if [[ -n "$AWG_SERVER_PUBKEY" ]]; then
    OUTBOUNDS="$(echo "$OUTBOUNDS" | jq \
      --arg ip "$SERVER_IP" \
      --arg port "$AWG_LISTEN_PORT" \
      --arg srvpub "$AWG_SERVER_PUBKEY" \
      --arg psk "$AWG_PSK" \
      --arg allowed "$AWG_ALLOWED_IPS" \
      '. += [{
         "type": "wireguard",
         "tag": "p2-amneziawg",
         "server": $ip,
         "server_port": ($port | tonumber),
         "local_address": [$allowed],
         "private_key": "<DEVICE_AWG_PRIVATE_KEY_FILL_LOCALLY>",
         "peer_public_key": $srvpub,
         "pre_shared_key": $psk
       }]')"
  fi
fi

# Add the standard "direct" + "block" + selector + urltest outbounds
OUTBOUNDS="$(echo "$OUTBOUNDS" | jq '
  . + [
    { "type": "selector", "tag": "select", "outbounds": ([.[].tag] + ["auto"]), "default": "auto", "interrupt_exist_connections": false },
    { "type": "urltest",  "tag": "auto",   "outbounds": [.[].tag],          "url": "https://www.gstatic.com/generate_204", "interval": "5m", "tolerance": 50 },
    { "type": "direct",   "tag": "direct" },
    { "type": "block",    "tag": "block" },
    { "type": "dns",      "tag": "dns-out" }
  ]')"

# Final config
jq -n \
  --arg client "$CLIENT_NAME" \
  --argjson outbounds "$OUTBOUNDS" \
  '{
    "log": { "level": "warn", "timestamp": true },
    "dns": {
      "servers": [
        { "tag": "remote", "address": "https://1.1.1.1/dns-query", "detour": "select" },
        { "tag": "local",  "address": "local", "detour": "direct" }
      ],
      "rules": [
        { "outbound": ["any"], "server": "local" }
      ]
    },
    "inbounds": [
      {
        "type": "tun",
        "tag": "tun-in",
        "interface_name": "tun0",
        "inet4_address": "172.19.0.1/30",
        "auto_route": true,
        "strict_route": true,
        "stack": "system",
        "sniff": true
      }
    ],
    "outbounds": $outbounds,
    "route": {
      "rules": [
        { "protocol": "dns", "outbound": "dns-out" },
        { "ip_is_private": true, "outbound": "direct" }
      ],
      "final": "select",
      "auto_detect_interface": true
    }
  }'
