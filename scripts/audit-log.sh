#!/usr/bin/env bash
# Append-only audit log for credential lifecycle events. Each event is
# an age-encrypted, ASCII-armored envelope appended to the operator's
# log file. Read side decrypts every envelope and prints JSON one
# record per line.
#
# Storage:
#   ~/.config/vpn-provision/audit.log.age  (mode 0600)
#
# Record schema:
#   {"ts": <unix>, "iso": "YYYY-MM-DDTHH:MM:SSZ",
#    "actor": "<whoami>@<host>", "action": "<verb>",
#    "client": "<name>", "env": "<env>", "provider": "<prov>",
#    "note": "<free-form>"}
#
# Writers:
#   scripts/audit-log.sh append --action issue-bootstrap \
#                               --client phone --note "OTP=…"
#   make audit-log-append ACTION=… CLIENT=… [NOTE=…]
#
# Reader:
#   scripts/audit-log.sh read           # prints JSONL of every event
#   make audit-log                      # equivalent
#
# Hooks: issue-bootstrap.sh writes one record per bootstrap URL issued.
# Other lifecycle scripts (new-client.sh, rotate-credentials.yml,
# warp-outbound rotation) are intentionally NOT auto-hooked yet — the
# expectation is to wire them per-operator as adoption proves the
# format. The append entry-point is stable.
set -euo pipefail

CONFIG_DIR="${HOME}/.config/vpn-provision"
AGE_KEY="${AGE_KEY:-${CONFIG_DIR}/age.key}"
LOG_FILE="${AUDIT_LOG_FILE:-${CONFIG_DIR}/audit.log.age}"
mkdir -p "$CONFIG_DIR"; chmod 0700 "$CONFIG_DIR"

cmd="${1:-}"; [[ -n "$cmd" ]] || { echo "usage: $0 append|read [args]" >&2; exit 1; }
shift || true

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 2; }
}
require age
require date

case "$cmd" in

  append)
    ACTION=""; CLIENT=""; ENVL="${ENV:-prod}"; PROVIDER="${PROVIDER:-upcloud}"; NOTE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --action)   ACTION="$2"; shift 2 ;;
        --client)   CLIENT="$2"; shift 2 ;;
        --env)      ENVL="$2"; shift 2 ;;
        --provider) PROVIDER="$2"; shift 2 ;;
        --note)     NOTE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
      esac
    done
    [[ -n "$ACTION" ]] || { echo "--action required" >&2; exit 1; }

    if [[ ! -f "$AGE_KEY" ]]; then
      echo "missing age key at $AGE_KEY — operator workstation not bootstrapped" >&2
      exit 2
    fi
    recipient="$(grep -m1 '^# public key:' "$AGE_KEY" | awk '{print $4}')"
    [[ -n "$recipient" ]] || { echo "could not parse age recipient from $AGE_KEY" >&2; exit 2; }

    actor="${AUDIT_ACTOR:-$(whoami)@$(hostname -s)}"
    ts="$(date -u +%s)"
    iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record="$(python3 -c "
import json, sys, os
print(json.dumps({
  'ts': int('$ts'), 'iso': '$iso', 'actor': '$actor',
  'action': '$ACTION', 'client': '$CLIENT' or None,
  'env': '$ENVL', 'provider': '$PROVIDER',
  'note': '$NOTE' or None,
}, sort_keys=True))
")"
    {
      printf '%s\n' "$record" | age -a -r "$recipient"
    } >> "$LOG_FILE"
    chmod 0600 "$LOG_FILE"
    echo "audit: ${ACTION} ${CLIENT:-<no-client>} → ${LOG_FILE}"
    ;;

  read)
    if [[ ! -f "$LOG_FILE" ]]; then
      echo "no audit log yet at ${LOG_FILE}" >&2
      exit 0
    fi
    [[ -f "$AGE_KEY" ]] || { echo "missing age key at $AGE_KEY" >&2; exit 2; }
    python3 - "$LOG_FILE" "$AGE_KEY" <<'PY'
import pathlib, re, subprocess, sys
log = pathlib.Path(sys.argv[1]).read_text()
key = sys.argv[2]
envelopes = re.findall(
    r"-----BEGIN AGE ENCRYPTED FILE-----.*?-----END AGE ENCRYPTED FILE-----\n?",
    log, flags=re.S,
)
for env in envelopes:
    r = subprocess.run(["age", "-d", "-i", key], input=env.encode(),
                       capture_output=True)
    if r.returncode != 0:
        print(f"# decrypt failed: {r.stderr.decode().strip()}", file=sys.stderr)
        continue
    sys.stdout.write(r.stdout.decode())
PY
    ;;

  *)
    echo "unknown subcommand: $cmd  (expected: append | read)" >&2
    exit 1
    ;;
esac