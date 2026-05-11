#!/usr/bin/env bash
# Resolve an IP or hostname through Team Cymru's whois interface and print
# a single tab-separated line: IP<TAB>ASN<TAB>ORG<TAB>COUNTRY.
# Empty fields stay empty; the row always has four columns. Exit 1 if
# Cymru is unreachable or returns an error envelope.
#
# Usage:
#   scripts/probe-asn.sh mirror.example.com
#   scripts/probe-asn.sh 1.2.3.4
#
# Used by validate-reality-target.sh and scan-reality-targets.sh as their
# common ASN lookup primitive. Run standalone via `make probe-asn HOST=…`.
set -euo pipefail

target="${1:-}"
[[ -n "$target" ]] || { echo "usage: $0 <ip|hostname>" >&2; exit 2; }

ip="$target"
if ! [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ip="$(getent hosts "$target" | awk '{print $1}' | head -1)"
  if [[ -z "$ip" ]]; then
    echo "could not resolve: $target" >&2
    exit 1
  fi
fi

line="$(whois -h whois.cymru.com " -v $ip" 2>/dev/null | tail -1 || true)"
if [[ -z "$line" ]] || echo "$line" | grep -qiE '^bulk|^error|<html'; then
  echo "Team Cymru lookup failed for $ip" >&2
  exit 1
fi

asn="$(   echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')"
prefix="$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')"
country="$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')"
org="$(   echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')"
printf '%s\t%s\t%s\t%s\t%s\n' "$ip" "$asn" "$prefix" "$country" "$org"