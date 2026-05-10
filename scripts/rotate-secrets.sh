#!/usr/bin/env bash
# Re-encrypt the secrets file under a new age recipient (or after editing).
# Wrapper around `sops updatekeys` + `sops --encrypt`.
set -euo pipefail

ENV="${ENV:-prod}"
SOPS_FILE="${SOPS_FILE:-${HOME}/.config/vpn-provision/${ENV}.secrets.sops.yaml}"

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "missing SOPS file: $SOPS_FILE" >&2
  exit 1
fi

# sops updatekeys reads the recipient list from .sops.yaml or env (SOPS_AGE_RECIPIENTS)
# and re-encrypts the data key without rewriting the payload.
sops updatekeys "$SOPS_FILE"

echo "updated keys on $SOPS_FILE"
echo "verify decryption: sops --decrypt $SOPS_FILE > /dev/null"
