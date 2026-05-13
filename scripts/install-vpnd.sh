#!/bin/sh
# install-vpnd.sh — download and install the vpnd binary from GitHub releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/po4yka/vpn-deploy/main/scripts/install-vpnd.sh | sh
#   PREFIX=/usr/local sh scripts/install-vpnd.sh
#
# Environment variables:
#   PREFIX      Installation prefix (default: /usr/local); binary goes to $PREFIX/bin/vpnd
#   ALLOW_ROOT  Set to 1 to permit running as root
#
# shellcheck shell=sh

set -eu

REPO="po4yka/vpn-deploy"
RELEASES_BASE="https://github.com/${REPO}/releases/latest/download"

# ---------------------------------------------------------------------------
# Root guard
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ "${ALLOW_ROOT:-0}" != "1" ]; then
  echo "error: refusing to run as root. Set ALLOW_ROOT=1 to override." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"

case "${os}" in
  Linux)
    case "${arch}" in
      x86_64)  target="x86_64-unknown-linux-gnu" ;;
      aarch64) target="aarch64-unknown-linux-gnu" ;;
      arm64)   target="aarch64-unknown-linux-gnu" ;;
      *)
        echo "error: unsupported Linux architecture: ${arch}" >&2
        exit 1
        ;;
    esac
    ;;
  Darwin)
    case "${arch}" in
      x86_64)  target="x86_64-apple-darwin" ;;
      arm64)   target="aarch64-apple-darwin" ;;
      *)
        echo "error: unsupported macOS architecture: ${arch}" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "error: unsupported operating system: ${os}" >&2
    exit 1
    ;;
esac

binary_name="vpnd-${target}"
binary_url="${RELEASES_BASE}/${binary_name}"
sums_url="${RELEASES_BASE}/SHA256SUMS"

# ---------------------------------------------------------------------------
# Working directory
# ---------------------------------------------------------------------------
tmpdir="$(mktemp -d)"
# Ensure cleanup on exit
trap 'rm -rf "${tmpdir}"' EXIT

# ---------------------------------------------------------------------------
# Download binary and checksums
# ---------------------------------------------------------------------------
echo "Downloading ${binary_name} ..."
curl -fsSL -o "${tmpdir}/vpnd" "${binary_url}"

echo "Downloading SHA256SUMS ..."
curl -fsSL -o "${tmpdir}/SHA256SUMS" "${sums_url}"

# ---------------------------------------------------------------------------
# Verify checksum
# ---------------------------------------------------------------------------
echo "Verifying checksum ..."

# Extract the expected hash for our binary from SHA256SUMS
expected="$(grep "${binary_name}" "${tmpdir}/SHA256SUMS" | awk '{print $1}')"

if [ -z "${expected}" ]; then
  echo "error: ${binary_name} not found in SHA256SUMS" >&2
  exit 1
fi

# Compute actual hash (sha256sum on Linux, shasum -a 256 on macOS)
if command -v sha256sum > /dev/null 2>&1; then
  actual="$(sha256sum "${tmpdir}/vpnd" | awk '{print $1}')"
elif command -v shasum > /dev/null 2>&1; then
  actual="$(shasum -a 256 "${tmpdir}/vpnd" | awk '{print $1}')"
else
  echo "error: neither sha256sum nor shasum found; cannot verify download" >&2
  exit 1
fi

if [ "${actual}" != "${expected}" ]; then
  echo "error: checksum mismatch" >&2
  echo "  expected: ${expected}" >&2
  echo "  actual:   ${actual}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install_dir="${PREFIX:-/usr/local}/bin"
install_path="${install_dir}/vpnd"

mkdir -p "${install_dir}"
cp "${tmpdir}/vpnd" "${install_path}"
chmod 0755 "${install_path}"

echo "vpnd installed to ${install_path}"
