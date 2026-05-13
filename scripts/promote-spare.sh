#!/usr/bin/env bash
# Consume the pending OTP from warm-spare-watcher and run blue-green.sh
# to swing traffic from BLUE_ENV to GREEN_ENV. Refuses if no OTP is
# pending, if the supplied OTP doesn't match, or if the OTP has expired.
#
# Usage:
#   make promote-spare OTP=<value>
#
# This is the operator's confirm step. The OTP gate prevents an
# attacker who compromised the ntfy topic from triggering a swap on
# their own — they would need both the topic and a way onto this
# workstation.
set -euo pipefail

PROVIDER="${PROVIDER:-upcloud}"
BLUE_ENV="${BLUE_ENV:-${ENV:-prod}}"
GREEN_ENV="${GREEN_ENV:-spare}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${HOME}/.cache/vpn-deploy/spare-state"
otp_file="${STATE_DIR}/pending-otp"
: "${OTP_TTL_SECONDS:=3600}"

given="${OTP:-${1:-}}"
[[ -n "$given" ]] || { echo "usage: $0 <OTP>   (or: make promote-spare OTP=<OTP>)" >&2; exit 1; }

if [[ ! -s "$otp_file" ]]; then
  echo "no pending OTP. warm-spare-watcher hasn't issued one." >&2
  exit 1
fi

stored="$(cut -f1 "$otp_file")"
mtime="$(cut -f2 "$otp_file")"
now=$(date +%s)
age=$(( now - mtime ))

if (( age > OTP_TTL_SECONDS )); then
  echo "OTP expired (${age}s old; TTL ${OTP_TTL_SECONDS}s). Re-run watch-spare to issue a new one." >&2
  rm -f "$otp_file"
  exit 1
fi

if [[ "$given" != "$stored" ]]; then
  echo "OTP does not match." >&2
  exit 1
fi

# OTP is valid — consume it immediately so it can't be replayed.
rm -f "$otp_file"

echo "OTP accepted. Running blue-green.sh ${PROVIDER}:${BLUE_ENV} → ${GREEN_ENV}…"
PROVIDER="$PROVIDER" BLUE_ENV="$BLUE_ENV" GREEN_ENV="$GREEN_ENV" \
  "${REPO_ROOT}/scripts/blue-green.sh"
