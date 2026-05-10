#!/usr/bin/env bash
# Decrypt the SOPS-encrypted secrets file into a temporary plaintext file with
# 0600 perms. Caller is responsible for shredding it after use (see Makefile
# target `clean`).
set -euo pipefail

ENV="${ENV:-prod}"
SOPS_FILE="${SOPS_FILE:-${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml}"
OUT="${SECRETS_FILE:-/tmp/vpn-${ENV}.secrets.yaml}"

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "missing SOPS file: $SOPS_FILE" >&2
  echo "create it with: sops --encrypt --age <recipient> ~/.config/vpn-provision/${ENV}.secrets.yaml > ${SOPS_FILE}" >&2
  exit 1
fi

sops --decrypt "$SOPS_FILE" > "$OUT"
chmod 0600 "$OUT"

echo "decrypted to $OUT"
echo "remember to shred after use: shred -u $OUT"
