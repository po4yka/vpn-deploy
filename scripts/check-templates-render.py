#!/usr/bin/env python3
"""Render every Jinja2 template against synthetic vars + example secrets.

This catches:
 - Jinja2 syntax errors that ansible-lint misses
 - JSON-invalid Xray config produced by the template
 - nginx config that won't pass `nginx -t` (we run the syntax checker if
   nginx is installed; otherwise skip)
 - Templates that crash on default cohort settings

Doesn't substitute for molecule; it's a fast pre-flight.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined, UndefinedError

REPO_ROOT = Path(__file__).resolve().parent.parent
ROLES_DIR = REPO_ROOT / "ansible" / "roles"
GROUP_VARS = REPO_ROOT / "ansible" / "group_vars"
EXAMPLE_FILE = REPO_ROOT / "secrets" / "prod.secrets.example.yaml"

# Static synthetic facts that templates may reference
SYNTHETIC_FACTS = {
    "ansible_user": "deploy",
    "ansible_architecture": "x86_64",
    "ansible_os_family": "Debian",
    "ansible_distribution": "Debian",
    "ansible_distribution_release": "trixie",
    "allowed_ssh_cidrs": ["198.51.100.42/32"],
}


def load_role_defaults() -> dict:
    out: dict = {}
    for defaults in ROLES_DIR.rglob("defaults/main.yml"):
        data = yaml.safe_load(defaults.read_text()) or {}
        # Merge top-level keys; later wins (consistent with Ansible precedence
        # for our purpose since each role uses its own top-level namespace)
        for k, v in data.items():
            if isinstance(v, dict) and isinstance(out.get(k), dict):
                out[k].update(v)
            else:
                out[k] = v
    return out


def merge_render_vars() -> dict:
    merged: dict = {}
    merged.update(load_role_defaults())

    all_yml = GROUP_VARS / "all.yml"
    if all_yml.exists():
        merged.update(yaml.safe_load(all_yml.read_text()) or {})

    if EXAMPLE_FILE.exists():
        merged.update(yaml.safe_load(EXAMPLE_FILE.read_text()) or {})

    merged.update(SYNTHETIC_FACTS)

    # Some role templates reference role-internal computed values via set_fact;
    # provide stand-ins so render doesn't UndefinedError.
    merged.setdefault("xray_arch", "64")
    merged.setdefault("xray_sha256", "0" * 64)
    merged.setdefault("hysteria_arch", "amd64")
    merged.setdefault("hysteria_sha256", "0" * 64)
    return merged


def render_template(path: Path, vars_: dict) -> str:
    import os
    import re as _re

    env = Environment(
        loader=FileSystemLoader(str(path.parent)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )
    # Polyfills for Ansible-only filters/tests we use.
    env.filters["to_json"] = lambda v: json.dumps(v)
    env.filters["quote"] = lambda v: "'" + str(v).replace("'", "'\\''") + "'"
    env.filters["dirname"] = lambda v: os.path.dirname(str(v))
    env.filters["basename"] = lambda v: os.path.basename(str(v))
    env.filters["regex_replace"] = lambda v, p, r: _re.sub(p, r, str(v))
    env.filters["regex_search"] = lambda v, p: (_re.search(p, str(v)).group(0) if _re.search(p, str(v)) else "")
    env.tests["match"] = lambda v, p: bool(_re.search(p, str(v)))
    env.tests["search"] = lambda v, p: bool(_re.search(p, str(v)))
    return env.get_template(path.name).render(**vars_)


def validate_json(text: str, label: str) -> str | None:
    try:
        json.loads(text)
        return None
    except json.JSONDecodeError as exc:
        return f"{label}: invalid JSON — {exc}"


def validate_nginx(text: str, label: str) -> str | None:
    """nginx syntax check. ssl_certificate / ssl_certificate_key / listen
    *ssl* directives reference files that don't exist on the CI runner;
    strip them so the test exercises only the surrounding directives. The
    real `nginx -t` against a deployed cert chain is covered by molecule
    scenarios for nginx-xhttp and subscription-host.
    """
    nginx = shutil.which("nginx")
    if not nginx:
        return None  # silently skip when nginx isn't available

    import re as _re
    stripped = _re.sub(
        r"^\s*ssl_(certificate|certificate_key|trusted_certificate)\s+[^;]+;",
        "    # ssl_certificate stripped for syntax-only check",
        text, flags=_re.MULTILINE,
    )
    stripped = _re.sub(
        r"\bssl(\s+(?:on|off))?\b",
        "",
        stripped,
    )
    # Remove `listen 443 ssl http2;` ssl/quic flags so nginx doesn't expect cert
    stripped = _re.sub(
        r"(\blisten\s+\S+)\s+ssl(\s+http2)?(\s+http3)?",
        r"\1\2\3",
        stripped,
    )
    # nginx 'add_header Strict-Transport-Security' on a non-ssl server is OK; leave.

    with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as fh:
        fh.write("events {}\nhttp {\n" + stripped + "\n}\n")
        path = fh.name
    try:
        result = subprocess.run(
            [nginx, "-t", "-c", path], capture_output=True, text=True
        )
        if result.returncode != 0:
            return f"{label}: nginx -t failed — {result.stderr.strip()}"
        return None
    finally:
        Path(path).unlink(missing_ok=True)


def main() -> int:
    vars_ = merge_render_vars()
    rendered = 0
    failures: list[str] = []

    for tpl in ROLES_DIR.rglob("*.j2"):
        rel = tpl.relative_to(REPO_ROOT)
        try:
            output = render_template(tpl, vars_)
        except UndefinedError as exc:
            failures.append(f"{rel}: undefined — {exc}")
            continue
        except Exception as exc:
            failures.append(f"{rel}: render error — {exc}")
            continue

        rendered += 1

        # Format-specific validation
        if tpl.name.endswith(".json.j2"):
            err = validate_json(output, str(rel))
            if err:
                failures.append(err)
        elif "nginx" in tpl.parent.parent.name and tpl.name.endswith(".conf.j2"):
            err = validate_nginx(output, str(rel))
            if err:
                failures.append(err)

    if failures:
        print("Template render check FAILED:")
        for f in failures:
            print(f"  {f}")
        return 1

    print(f"OK — {rendered} templates rendered cleanly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
