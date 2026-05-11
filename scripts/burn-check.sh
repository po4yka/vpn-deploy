#!/usr/bin/env bash
# External reachability probe for the current VPN VPS IP.
#
# Uses check-host.net's public node API to test TCP/443 reachability from
# multiple geographic vantage points, including RU. Exits non-zero if N or
# more nodes fail. Intended to run from cron on the operator workstation.
#
# Usage:
#   scripts/burn-check.sh                      # uses defaults
#   FAIL_THRESHOLD=3 scripts/burn-check.sh
#   NODES="ru1.node.check-host.net,ru4.node.check-host.net,uk1.node.check-host.net" \
#     scripts/burn-check.sh
#
# Required env:
#   PROVIDER (default: upcloud)
#   ENV      (default: prod)
set -euo pipefail

PROVIDER="${PROVIDER:-upcloud}"
ENV="${ENV:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/providers/${PROVIDER}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-2}"
DEFAULT_NODES="ru1.node.check-host.net,ru2.node.check-host.net,ru4.node.check-host.net,de1.node.check-host.net"
NODES="${NODES:-$DEFAULT_NODES}"

for tool in curl jq terraform; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done

IP="$(terraform -chdir="$TF_DIR" output -raw server_ipv4)"

# check-host.net rest API: GET /check-tcp?host=<ip>:<port>&node=<n1>&node=<n2>…
# returns a request_id; results are polled at /check-result/<request_id>.
NODE_PARAMS="$(echo "$NODES" | tr ',' '\n' | sed 's/^/\&node=/' | tr -d '\n')"
REQ="$(curl -fsS -H 'Accept: application/json' \
  "https://check-host.net/check-tcp?host=${IP}:443${NODE_PARAMS}")"
REQUEST_ID="$(echo "$REQ" | jq -r .request_id)"

if [[ -z "$REQUEST_ID" || "$REQUEST_ID" == "null" ]]; then
  echo "check-host.net rejected the request:" >&2
  echo "$REQ" >&2
  exit 2
fi

# Poll up to 30s for results
for _ in $(seq 1 15); do
  sleep 2
  RESULT="$(curl -fsS -H 'Accept: application/json' \
    "https://check-host.net/check-result/${REQUEST_ID}")"
  # Result is a map of node→[[result_object]] or null while pending. If every
  # node has a non-null array we're done.
  PENDING="$(echo "$RESULT" | jq '[to_entries[] | select(.value == null)] | length')"
  [[ "$PENDING" == "0" ]] && break
done

# Count nodes whose first result didn't include an "address" field success.
# A successful check-tcp result looks like: {"address":"…","time":0.123}.
# Failures look like {"error":"Connection refused"} or {"error":"Connection timed out"}.
TOTAL="$(echo "$RESULT" | jq 'length')"
FAILS="$(echo "$RESULT" | jq '[to_entries[]
  | .key as $node
  | (.value // [[]])[0] // []
  | (.[0] // {})
  | select(.error != null or (.address // null) == null)
  ] | length')"

echo "burn-check: ${PROVIDER}/${ENV} ${IP}:443  →  ${TOTAL} nodes probed, ${FAILS} failed"
echo "$RESULT" | jq -r 'to_entries[] | "  \(.key): \(.value // "pending")"'

# Optional Prometheus textfile export. When NODE_EXPORTER_TEXTFILE_DIR is
# set, write {dir}/vpn_burn.prom with one gauge per node and a summary.
# Atomic write: tmp + mv per the textfile-collector contract.
if [[ -n "${NODE_EXPORTER_TEXTFILE_DIR:-}" ]]; then
  out="${NODE_EXPORTER_TEXTFILE_DIR%/}/vpn_burn.prom"
  tmp="${out}.tmp.$$"
  {
    echo "# HELP vpn_burn_total_nodes Number of vantage points probed"
    echo "# TYPE vpn_burn_total_nodes gauge"
    echo "vpn_burn_total_nodes{provider=\"${PROVIDER}\",env=\"${ENV}\"} ${TOTAL}"
    echo "# HELP vpn_burn_failed_nodes Number of probes that did not connect"
    echo "# TYPE vpn_burn_failed_nodes gauge"
    echo "vpn_burn_failed_nodes{provider=\"${PROVIDER}\",env=\"${ENV}\"} ${FAILS}"
    echo "# HELP vpn_burn_reachable Whether the VPS public port appears reachable per node (1 OK / 0 failed)"
    echo "# TYPE vpn_burn_reachable gauge"
    echo "$RESULT" | jq -r --arg p "$PROVIDER" --arg e "$ENV" '
      to_entries[]
      | .key as $node
      | (.value // [[]])[0] // []
      | (.[0] // {})
      | (if (.address // null) != null and (.error // null) == null then 1 else 0 end) as $ok
      | "vpn_burn_reachable{provider=\"\($p)\",env=\"\($e)\",node=\"\($node)\"} \($ok)"
    '
    echo "# HELP vpn_burn_last_run_unixtime Last time burn-check ran"
    echo "# TYPE vpn_burn_last_run_unixtime gauge"
    echo "vpn_burn_last_run_unixtime{provider=\"${PROVIDER}\",env=\"${ENV}\"} $(date +%s)"
  } > "$tmp"
  mv "$tmp" "$out"
  chmod 0644 "$out"
fi

if (( FAILS >= FAIL_THRESHOLD )); then
  echo "FAIL: ${FAILS} of ${TOTAL} nodes could not reach ${IP}:443 — IP may be burned" >&2
  exit 1
fi

echo "OK"
