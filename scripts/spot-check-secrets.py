#!/usr/bin/env python3
"""Pre-deploy sanity check on a decrypted secrets file.

Walks the YAML tree and flags anything that would deploy as a known-bad
value: REPLACE_WITH_* placeholders, expired or self-signed cert PEMs,
H1..H4 still as strings, weak passwords, plaintext cloudflare default
target, etc.

Reads $VPN_SECRETS_FILE (set by `make decrypt`) or the path passed as
the first argument. Exits 0 on clean; non-zero on any finding.

Run via `make spot-check-secrets`.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

PLACEHOLDER_RE = re.compile(r"REPLACE_WITH_")
OVERUSED_TARGETS = {
    "www.cloudflare.com", "cloudflare.com",
    "www.microsoft.com", "microsoft.com",
    "www.apple.com", "apple.com",
    "www.google.com", "google.com",
    "discord.com", "icloud.com",
}


class Findings:
    def __init__(self) -> None:
        self.items: list[tuple[str, str]] = []

    def add(self, where: str, msg: str) -> None:
        self.items.append((where, msg))

    def __bool__(self) -> bool:
        return bool(self.items)


def walk_for_placeholders(data, path: str, f: Findings) -> None:
    if isinstance(data, str):
        if PLACEHOLDER_RE.search(data):
            f.add(path, f"placeholder still present ({data[:40]!r})")
    elif isinstance(data, dict):
        for k, v in data.items():
            walk_for_placeholders(v, f"{path}.{k}" if path else k, f)
    elif isinstance(data, list):
        for i, v in enumerate(data):
            walk_for_placeholders(v, f"{path}[{i}]", f)


def check_cert_pem(pem: str, key_pem: str | None, path: str, f: Findings) -> None:
    if not pem or PLACEHOLDER_RE.search(pem):
        return  # placeholder branch handled separately
    try:
        end_date = subprocess.run(
            ["openssl", "x509", "-noout", "-enddate"],
            input=pem.encode(), capture_output=True, check=True,
        ).stdout.decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        f.add(path, f"openssl rejected cert_pem ({exc})")
        return
    m = re.search(r"notAfter=(.+)$", end_date)
    if not m:
        f.add(path, f"could not parse notAfter from {end_date!r}")
        return
    not_after = datetime.strptime(m.group(1), "%b %d %H:%M:%S %Y %Z")
    days = (not_after.replace(tzinfo=timezone.utc) - datetime.now(tz=timezone.utc)).days
    if days < 0:
        f.add(path, f"cert expired {-days} days ago ({not_after.date()})")
    elif days < 14:
        f.add(path, f"cert expires in {days} days ({not_after.date()}) — renew now")

    try:
        issuer = subprocess.run(
            ["openssl", "x509", "-noout", "-issuer"],
            input=pem.encode(), capture_output=True, check=True,
        ).stdout.decode().strip()
    except subprocess.CalledProcessError:
        return
    if " CN=" in issuer and issuer.split("CN=", 1)[1].strip() == \
            subprocess.run(["openssl", "x509", "-noout", "-subject"],
                           input=pem.encode(), capture_output=True, check=True,
                           ).stdout.decode().split("CN=", 1)[1].strip():
        f.add(path, "cert appears self-signed (issuer == subject)")

    if key_pem and not PLACEHOLDER_RE.search(key_pem):
        try:
            cert_mod = subprocess.run(
                ["openssl", "x509", "-noout", "-modulus"],
                input=pem.encode(), capture_output=True, check=True,
            ).stdout.decode().strip()
            # try RSA first, then EC
            key_mod_cmd = ["openssl", "rsa", "-noout", "-modulus"]
            key_mod = subprocess.run(
                key_mod_cmd, input=key_pem.encode(),
                capture_output=True, check=False,
            )
            if key_mod.returncode == 0 and key_mod.stdout.strip() != cert_mod.encode():
                f.add(path, "RSA cert modulus does not match key modulus")
        except subprocess.CalledProcessError:
            pass


def main() -> int:
    src = os.environ.get("VPN_SECRETS_FILE") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not src:
        print("usage: VPN_SECRETS_FILE=/tmp/vpn-prod.secrets.yaml scripts/spot-check-secrets.py", file=sys.stderr)
        return 2
    path = Path(src)
    if not path.exists():
        print(f"missing: {path}", file=sys.stderr)
        return 2
    data = yaml.safe_load(path.read_text())

    f = Findings()

    walk_for_placeholders(data, "", f)

    xray = (data or {}).get("xray") or {}
    target = xray.get("target", "")
    host = target.split(":", 1)[0]
    if host in OVERUSED_TARGETS:
        f.add("xray.target",
              f"{host!r} is over-templated — pick a less-used target")

    if not (xray.get("reality_private_key") or "").strip() or \
       PLACEHOLDER_RE.search(xray.get("reality_private_key", "")):
        f.add("xray.reality_private_key", "missing")
    if not (xray.get("reality_public_key") or "").strip() or \
       PLACEHOLDER_RE.search(xray.get("reality_public_key", "")):
        f.add("xray.reality_public_key", "missing")

    for client in xray.get("clients") or []:
        sid = client.get("short_id", "")
        if not re.fullmatch(r"[0-9a-fA-F]{2,16}", sid):
            f.add(f"xray.clients[{client.get('name','?')}].short_id",
                  f"not hex / wrong length ({sid!r})")

    for role, key in (("nginx_xhttp", "key_pem"),
                      ("hysteria", "key_pem"),
                      ("naive_secrets", "key_pem")):
        block = data.get(role) or {}
        check_cert_pem(block.get("cert_pem", ""), block.get(key, ""),
                       f"{role}.cert_pem", f)

    awg = (data or {}).get("amneziawg_secrets") or {}
    for h in ("h1", "h2", "h3", "h4"):
        v = awg.get(h)
        if not isinstance(v, int) or v == 0:
            f.add(f"amneziawg_secrets.{h}", f"expected non-zero int, got {v!r}")

    for client in (data.get("hysteria") or {}).get("clients") or []:
        pw = client.get("password", "")
        if len(pw) < 16:
            f.add(f"hysteria.clients[{client.get('name','?')}].password",
                  f"password length {len(pw)} < 16")

    restic = (data.get("backup") or {}).get("restic_password", "")
    if len(restic) < 32:
        f.add("backup.restic_password",
              f"length {len(restic)} < 32 — run openssl rand -base64 32")

    if not f:
        print("OK — no findings.")
        return 0

    print(f"{len(f.items)} finding(s):")
    for where, msg in f.items:
        print(f"  {where}: {msg}")
    return 1


if __name__ == "__main__":
    sys.exit(main())