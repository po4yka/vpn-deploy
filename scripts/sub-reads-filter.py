#!/usr/bin/env python3
"""Filter the subscription read-audit JSONL stream by time / route / count.

Reads JSONL on stdin, writes JSONL on stdout. Replaces the inline `eval`
pipeline that previously lived in scripts/sub-reads.sh — see
scripts/CLAUDE.md "Never eval" rule.

Argument values are read from argv, not spliced into source — so operator
input cannot inject Python or shell.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import deque


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--since",
        type=str,
        default="",
        help="RFC-3339 timestamp (e.g. 2026-05-01 or 2026-05-01T12:00:00). "
             "Records older than this are dropped.",
    )
    parser.add_argument(
        "--route",
        type=str,
        default="",
        choices=("", "sub", "bootstrap"),
        help="If set, keep only records whose 'route' field matches.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="If > 0, keep only the most recent N records (tail-style).",
    )
    args = parser.parse_args()

    cutoff: dt.datetime | None = None
    if args.since:
        cutoff = dt.datetime.fromisoformat(args.since).replace(tzinfo=dt.timezone.utc)

    buffer: deque[str] = deque(maxlen=args.limit if args.limit > 0 else None)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue

        if cutoff is not None:
            ts = dt.datetime.fromtimestamp(rec.get("ts", 0), tz=dt.timezone.utc)
            if ts < cutoff:
                continue

        if args.route and rec.get("route") != args.route:
            continue

        if args.limit > 0:
            buffer.append(line)
        else:
            sys.stdout.write(line + "\n")

    if args.limit > 0:
        sys.stdout.write("\n".join(buffer))
        if buffer:
            sys.stdout.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
