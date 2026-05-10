#!/usr/bin/env bash
# Reconstruct the operator's age private key from T Shamir shares.
#
# Usage:
#   scripts/age-recovery-combine.sh <threshold>
# Then paste the T shares one per line. Output goes to stdout — pipe to
# a file with mode 0600.
#
# Example:
#   scripts/age-recovery-combine.sh 2 > ~/.config/vpn-provision/age.key
#   chmod 0600 ~/.config/vpn-provision/age.key
set -euo pipefail

T="${1:-}"
if [[ -z "$T" ]]; then
  echo "usage: $0 <threshold>" >&2
  exit 1
fi

command -v ssss-combine >/dev/null 2>&1 || {
  echo "missing: ssss-combine" >&2
  exit 1
}

cat >&2 <<EOF
Paste your $T shares, one per line. Each share starts with a number and a dash
(e.g. "1-...", "2-..."). Press Ctrl-D when done.

EOF

KEY="$(ssss-combine -t "$T" -Q)"

if [[ "$KEY" != AGE-SECRET-KEY-* ]]; then
  echo "reconstruction did not produce a valid age secret key" >&2
  exit 1
fi

# Emit a properly formatted age key file
cat <<EOF
# created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# reconstructed from ssss shares
$KEY
EOF
