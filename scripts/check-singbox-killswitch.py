#!/usr/bin/env python3
"""Validate that an emitted sing-box client bundle has the kill-switch
properties we expect — no clear-text leak when the tunnel is down,
no DNS leak around it, no fall-through to a "direct" outbound that
would silently bypass the proxy.

Rules (each MUST pass, list grows over time):

  K1  TUN inbound has auto_route=true AND strict_route=true
  K2  TUN inbound has sniff=true (so app traffic is identified)
  K3  Route block has a "final" of "select" or "auto" — never "direct"
  K4  DNS servers route the "remote" server via the tunnel (detour to
      a non-direct outbound)
  K5  No outbound carries an explicit "domain_strategy":"ipv6_only" or
      "prefer_ipv6" — those bypass v4-only tunnels silently. (Mixed-
      stack is fine when the TUN is dual-stack; we accept ipv4_only
      and prefer_ipv4.)

Each failure prints a short reason. Exit 0 clean, 1 on findings.

Usage:
  scripts/check-singbox-killswitch.py phone.singbox.json
  make emit-singbox CLIENT=phone > /tmp/phone.json \\
    && scripts/check-singbox-killswitch.py /tmp/phone.json
"""
from __future__ import annotations

import json
import pathlib
import sys


def check(bundle: dict) -> list[str]:
    findings: list[str] = []

    inbounds = bundle.get("inbounds") or []
    tun = next((i for i in inbounds if i.get("type") == "tun"), None)
    if tun is None:
        findings.append("K1: no TUN inbound at all — bundle isn't a kill-switch config")
        return findings
    if not tun.get("auto_route"):
        findings.append("K1: TUN inbound.auto_route is falsy")
    if not tun.get("strict_route"):
        findings.append("K1: TUN inbound.strict_route is falsy")
    if not tun.get("sniff"):
        findings.append("K2: TUN inbound.sniff is falsy")

    route = bundle.get("route") or {}
    final = route.get("final")
    if final == "direct":
        findings.append("K3: route.final == 'direct' — tunnel-down apps egress in clear")
    elif final not in ("select", "auto"):
        findings.append(f"K3: route.final is {final!r}, expected 'select' or 'auto'")

    dns = bundle.get("dns") or {}
    for server in dns.get("servers") or []:
        if server.get("tag") == "remote":
            if server.get("detour") in (None, "direct"):
                findings.append(
                    "K4: dns.servers.remote.detour is direct (DNS leaks to ISP)"
                )

    for ob in bundle.get("outbounds") or []:
        ds = ob.get("domain_strategy")
        if ds in ("ipv6_only", "prefer_ipv6"):
            findings.append(
                f"K5: outbound tag={ob.get('tag','?')!r} has domain_strategy={ds!r} — IPv6 may bypass an IPv4-only tunnel"
            )

    return findings


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: check-singbox-killswitch.py <bundle.json>", file=sys.stderr)
        return 2
    path = pathlib.Path(argv[0])
    if not path.is_file():
        # Allow stdin via "-"
        if argv[0] == "-":
            bundle = json.load(sys.stdin)
        else:
            print(f"missing: {path}", file=sys.stderr)
            return 2
    else:
        bundle = json.loads(path.read_text())

    findings = check(bundle)
    if not findings:
        print("OK — kill-switch properties verified (K1-K5)")
        return 0
    print(f"{len(findings)} finding(s):")
    for f in findings:
        print(f"  {f}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
