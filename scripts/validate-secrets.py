#!/usr/bin/env python3
"""Validate a secrets YAML file against the formal schema.

The schema (secrets/schema.json) is the contract that every Ansible
role consumes at deploy time. Today a malformed entry (missing key,
wrong type, fragmented URL) surfaces as a render-time error on the
VPS — `xray test -config` fails, or the role's restart handler dies
mid-play. This script catches that drift at PR time and at the
operator's pre-deploy-check stage.

Modes:
  default                Lenient: accepts REPLACE_WITH_* placeholders.
                         This is what runs in pre-commit on the example
                         schema and what an operator runs against a
                         half-filled draft.
  --strict               Reject any REPLACE_WITH_* placeholder. This is
                         what runs in pre-deploy-check against the real
                         decrypted secrets file.

Default input: VPN_SECRETS_FILE if set, otherwise
secrets/prod.secrets.example.yaml.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA = REPO_ROOT / "secrets" / "schema.json"
DEFAULT_TARGET = REPO_ROOT / "secrets" / "prod.secrets.example.yaml"

PLACEHOLDER = re.compile(r"REPLACE_WITH_[A-Z0-9_]+")


def _walk_strings(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from _walk_strings(v, f"{path}.{k}" if path else str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from _walk_strings(v, f"{path}[{i}]")
    elif isinstance(node, str):
        yield path, node


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "secrets_file",
        nargs="?",
        help="Path to a secrets YAML file. Defaults to "
        "$VPN_SECRETS_FILE or secrets/prod.secrets.example.yaml.",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="Reject any REPLACE_WITH_* placeholder. Run this against "
        "real secrets before deploy.",
    )
    args = ap.parse_args()

    target = (
        Path(args.secrets_file)
        if args.secrets_file
        else Path(os.environ.get("VPN_SECRETS_FILE") or DEFAULT_TARGET)
    )
    if not target.is_file():
        print(f"validate-secrets: not a file: {target}", file=sys.stderr)
        return 2

    try:
        import jsonschema
    except ImportError:
        print(
            "validate-secrets: missing 'jsonschema' — `pip install jsonschema`",
            file=sys.stderr,
        )
        return 2

    schema = json.loads(SCHEMA.read_text())
    try:
        doc = yaml.safe_load(target.read_text()) or {}
    except yaml.YAMLError as exc:
        print(f"validate-secrets: YAML parse error: {exc}", file=sys.stderr)
        return 1

    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path))
    if errors:
        print(f"validate-secrets: {len(errors)} schema violation(s) in {target}:",
              file=sys.stderr)
        for e in errors:
            loc = ".".join(str(p) for p in e.absolute_path) or "<root>"
            print(f"  {loc}: {e.message}", file=sys.stderr)
        return 1

    if args.strict:
        offenders = []
        for path, value in _walk_strings(doc):
            if PLACEHOLDER.search(value):
                offenders.append((path, value))
        if offenders:
            print(
                f"validate-secrets: --strict found {len(offenders)} "
                f"unfilled REPLACE_WITH_* placeholder(s) in {target}:",
                file=sys.stderr,
            )
            for path, value in offenders[:20]:
                short = value if len(value) < 60 else value[:57] + "..."
                print(f"  {path}: {short}", file=sys.stderr)
            if len(offenders) > 20:
                print(f"  ... and {len(offenders) - 20} more", file=sys.stderr)
            return 1

    print(f"validate-secrets: OK — {target} conforms to schema"
          + (" (strict)" if args.strict else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
