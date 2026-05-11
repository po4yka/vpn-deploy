#!/usr/bin/env bash
# Check the deployed VPS public IP against well-known reputation lists.
# Daily run cadence — costs three DNS queries plus one HTTPS call when
# ABUSEIPDB_KEY is set.
#
# Lists consulted:
#   Spamhaus DROP / EDROP (DNS RBL: zen.spamhaus.org)
#   FireHOL Level 1 IP set (HTTPS; cached 24 h)
#   AbuseIPDB confidence-of-abuse score (HTTPS; needs ABUSEIPDB_KEY)
#
# On finding, exits 1 and (when ntfy is configured) sends an alert.
#
# Usage:
#   PROVIDER=upcloud ENV=prod scripts/check-ip-reputation.sh
#   IP=1.2.3.4 scripts/check-ip-reputation.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${HOME}/.cache/vpn-deploy"
mkdir -p "$CACHE_DIR"

PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"

if [[ -z "${IP:-}" ]]; then
  TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
  IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4 2>/dev/null || true)"
fi
if [[ -z "${IP:-}" ]]; then
  echo "no IP available (terraform output missing? export IP=… to override)" >&2
  exit 2
fi

# Reverse the IP for RBL lookups.
IFS=. read -r a b c d <<< "$IP"
rev="${d}.${c}.${b}.${a}"

findings=()

# ---------------------------------------------------------------------------
# Spamhaus zen — DNS query; A response means listed.
# ---------------------------------------------------------------------------
spamhaus_q="${rev}.zen.spamhaus.org"
spam_resp="$(dig +short "$spamhaus_q" A 2>/dev/null | head -1 || true)"
if [[ -n "$spam_resp" ]]; then
  # Spamhaus refuses responses to public/open resolvers and signals it with
  # 127.255.255.x sentinel codes. Don't treat those as a real listing —
  # they mean "lookup unreliable from this resolver".
  if [[ "$spam_resp" =~ ^127\.255\.255\. ]]; then
    echo "  (info) Spamhaus zen returned the open-resolver sentinel ${spam_resp};" \
         "lookup unreliable — use a private DNS resolver or DNSBL contributor account" >&2
  else
    findings+=("Spamhaus zen: listed (response=$spam_resp)")
  fi
fi

# ---------------------------------------------------------------------------
# FireHOL Level 1 — daily-refreshed IP set; download once a day.
# ---------------------------------------------------------------------------
fh_cache="${CACHE_DIR}/firehol_level1.netset"
fh_url="https://iplists.firehol.org/files/firehol_level1.netset"
if [[ ! -f "$fh_cache" ]] || [[ -n "$(find "$fh_cache" -mtime +1 -print 2>/dev/null)" ]]; then
  curl -fsSL --max-time 30 -o "${fh_cache}.tmp" "$fh_url" \
    && mv "${fh_cache}.tmp" "$fh_cache" \
    || echo "(warning) failed to refresh FireHOL list; using cached copy" >&2
fi
if [[ -f "$fh_cache" ]] && python3 -c "
import ipaddress, pathlib, sys
ip = ipaddress.ip_address('$IP')
for line in pathlib.Path('$fh_cache').read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#'): continue
    if ip in ipaddress.ip_network(line, strict=False):
        sys.exit(0)
sys.exit(1)
"; then
  findings+=("FireHOL Level 1: listed in $fh_cache")
fi

# ---------------------------------------------------------------------------
# AbuseIPDB — optional, only if key is provided.
# ---------------------------------------------------------------------------
if [[ -n "${ABUSEIPDB_KEY:-}" ]]; then
  score="$(curl -fsS --max-time 10 \
    -H "Key: ${ABUSEIPDB_KEY}" -H "Accept: application/json" \
    "https://api.abuseipdb.com/api/v2/check?ipAddress=${IP}&maxAgeInDays=30" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['abuseConfidenceScore'])" 2>/dev/null || true)"
  if [[ "${score:-0}" =~ ^[0-9]+$ ]] && (( score >= 25 )); then
    findings+=("AbuseIPDB: abuseConfidenceScore=${score}")
  fi
fi

echo "IP=${IP}  provider=${PROVIDER}  env=${ENV}"
if (( ${#findings[@]} == 0 )); then
  echo "OK — IP reputation clean"
  exit 0
fi

printf '  - %s\n' "${findings[@]}"

if [[ -n "${NTFY_TOPIC:-}" ]]; then
  NTFY_URL="${NTFY_URL:-https://ntfy.sh}"
  auth=()
  [[ -n "${NTFY_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${NTFY_TOKEN}")
  msg="IP reputation finding on ${PROVIDER}:${ENV} IP=${IP}
$(printf '%s\n' "${findings[@]}")"
  curl -fsS -X POST \
    -H "Title: IP reputation: ${PROVIDER}:${ENV}" \
    -H "Priority: high" \
    -H "Tags: warning,vpn,ip-reputation" \
    "${auth[@]}" \
    --data "$msg" \
    "${NTFY_URL%/}/${NTFY_TOPIC}" >/dev/null || true
fi
exit 1