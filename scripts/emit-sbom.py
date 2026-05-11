#!/usr/bin/env python3
"""Emit a CycloneDX 1.5 SBOM for the pinned deploy.

Source of truth for pinned binaries:
  * secrets/prod.secrets.example.yaml — versions + release sha256s for
    xray, hysteria, geodata pins
  * scripts/scan-reality-targets.sh — RealiTLScanner pin
  * AmneziaWG go / tools — version strings from the schema (sha256
    pinning isn't part of v1 schema; recorded as "not-pinned")

System packages (restic, age, sops, gitleaks) live in the operator
workstation / VPS distro and are out of scope — those are tracked by
the host's package manager, not this repo.

Usage:
  scripts/emit-sbom.py                       # writes sbom/example.json
  VPN_SECRETS_FILE=/tmp/vpn-prod.secrets.yaml scripts/emit-sbom.py
                                             # writes sbom/<env>.json
"""
from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import pathlib
import re
import sys
import uuid

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SECRETS = REPO_ROOT / "secrets" / "prod.secrets.example.yaml"
SBOM_DIR = REPO_ROOT / "sbom"
SBOM_DIR.mkdir(exist_ok=True)


def _purl(scheme: str, *parts: str, **q: str) -> str:
    """Build a Package URL string."""
    base = f"pkg:{scheme}/" + "/".join(parts)
    if q:
        base += "?" + "&".join(f"{k}={v}" for k, v in q.items() if v)
    return base


def _release_hash(label: str, value: str | None) -> dict | None:
    if not value or value == "REPLACE_WITH_RELEASE_SHA256":
        return None
    return {"alg": "SHA-256", "content": value, "label": label}


def component(name: str, version: str, purl: str, hashes: list[dict],
              source_url: str, description: str) -> dict:
    bom_ref = f"{name}@{version}"
    c: dict = {
        "type": "application",
        "bom-ref": bom_ref,
        "name": name,
        "version": version,
        "purl": purl,
        "externalReferences": [
            {"type": "distribution", "url": source_url},
        ],
        "description": description,
    }
    real_hashes = [h for h in hashes if h]
    if real_hashes:
        # CycloneDX hash entries don't carry our extra "label" — drop it
        c["hashes"] = [{"alg": h["alg"], "content": h["content"]} for h in real_hashes]
    return c


def reali_pin() -> tuple[str, str]:
    """Read the pinned RealiTLScanner version + sha256 from the script."""
    src = (REPO_ROOT / "scripts" / "scan-reality-targets.sh").read_text()
    ver = re.search(r'REALI_VERSION="([^"]+)"', src)
    sha = re.search(r'REALI_LINUX_SHA256="([^"]+)"', src)
    return (ver.group(1) if ver else "unknown",
            sha.group(1) if sha else "")


def main() -> int:
    src_path = pathlib.Path(os.environ.get("VPN_SECRETS_FILE") or DEFAULT_SECRETS)
    if not src_path.exists():
        print(f"missing: {src_path}", file=sys.stderr)
        return 2
    data = yaml.safe_load(src_path.read_text()) or {}
    label = "example" if src_path == DEFAULT_SECRETS else src_path.stem

    components: list[dict] = []

    xray = data.get("xray") or {}
    if "version" in xray:
        components.append(component(
            "xray-core",
            xray["version"],
            _purl("github", "XTLS", "Xray-core", version=xray["version"]),
            [
                _release_hash("linux_amd64", xray.get("linux_amd64_sha256")),
                _release_hash("linux_arm64", xray.get("linux_arm64_sha256")),
            ],
            f"https://github.com/XTLS/Xray-core/releases/tag/{xray['version']}",
            "P0 transport — VLESS+REALITY+XTLS-Vision",
        ))

    hys = data.get("hysteria") or {}
    if "version" in hys:
        components.append(component(
            "hysteria",
            hys["version"],
            _purl("github", "apernet", "hysteria", version=hys["version"]),
            [
                _release_hash("linux_amd64", hys.get("linux_amd64_sha256")),
                _release_hash("linux_arm64", hys.get("linux_arm64_sha256")),
            ],
            f"https://github.com/apernet/hysteria/releases/tag/{hys['version']}",
            "P2 transport — Hysteria2 UDP/QUIC",
        ))

    geo = data.get("geodata") or {}
    if geo.get("geosite_url"):
        components.append(component(
            "geosite",
            "pinned",
            _purl("generic", "geosite", url=geo["geosite_url"]),
            [_release_hash("geosite", geo.get("geosite_sha256"))],
            geo["geosite_url"],
            "Xray routing geosite database",
        ))
    if geo.get("geoip_url"):
        components.append(component(
            "geoip",
            "pinned",
            _purl("generic", "geoip", url=geo["geoip_url"]),
            [_release_hash("geoip", geo.get("geoip_sha256"))],
            geo["geoip_url"],
            "Xray routing geoip database",
        ))

    awg_go = data.get("amneziawg_go_version")
    awg_tools = data.get("amneziawg_tools_version")
    if awg_go:
        components.append(component(
            "amneziawg-go", awg_go,
            _purl("github", "amnezia-vpn", "amneziawg-go", version=awg_go),
            [],
            f"https://github.com/amnezia-vpn/amneziawg-go/releases/tag/{awg_go}",
            "Userspace AmneziaWG implementation (no sha256 pin in v1 schema)",
        ))
    if awg_tools:
        components.append(component(
            "amneziawg-tools", awg_tools,
            _purl("github", "amnezia-vpn", "amneziawg-tools", version=awg_tools),
            [],
            f"https://github.com/amnezia-vpn/amneziawg-tools/releases/tag/{awg_tools}",
            "AmneziaWG userspace tools (no sha256 pin in v1 schema)",
        ))

    reali_ver, reali_sha = reali_pin()
    components.append(component(
        "RealiTLScanner", reali_ver,
        _purl("github", "XTLS", "RealiTLScanner", version=reali_ver),
        [_release_hash("linux-amd64", reali_sha)],
        f"https://github.com/XTLS/RealiTLScanner/releases/tag/{reali_ver}",
        "Operator-side REALITY target scanner",
    ))

    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "metadata": {
            "timestamp": _dt.datetime.now(tz=_dt.timezone.utc).isoformat(timespec="seconds"),
            "tools": [{"name": "scripts/emit-sbom.py"}],
            "component": {
                "type": "application",
                "name": "vpn-deploy",
                "version": label,
                "description": "Reproducible VPN deployment automation",
            },
        },
        "components": components,
    }

    out = SBOM_DIR / f"{label}.json"
    payload = json.dumps(sbom, indent=2, sort_keys=False) + "\n"
    out.write_text(payload)
    digest = hashlib.sha256(payload.encode()).hexdigest()[:16]
    print(f"wrote {out}  ({len(components)} components, sha256: {digest}…)")
    return 0


if __name__ == "__main__":
    sys.exit(main())