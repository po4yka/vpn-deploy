---
name: bash-scripting
description: Bash conventions for vpn-deploy scripts/ — strict mode, shellcheck gates, SOPS handling, no piped installers. Use when editing scripts/**, role-level shell tasks, or Makefile recipes. vpn-deploy project variant.
---

# Bash Scripting (vpn-deploy)

All shell in this repo runs under strict mode, passes shellcheck, and never touches plaintext
secrets on disk. The canonical example is `scripts/render-inventory.sh`.

## Hard rules

- **Always strict mode**: `set -euo pipefail` at the top, plus `IFS=$'\n\t'` if word
  splitting matters.
- **`#!/usr/bin/env bash` shebang.** Not `/bin/bash` (portability) and never `/bin/sh`
  (this code uses bash features).
- **Pass `shellcheck`** — `make ci-fast` runs it. No `# shellcheck disable=` without a
  one-line justification comment above.
- **No piped installers.** Never `curl ... | bash`, never `wget -O- ... | sh`. Use
  `get_url` (Ansible) or `apt`/`dpkg` with a pinned version. Binaries fetched via curl get
  a `sha256sum -c` check before exec.
- **No plaintext secrets on disk.** SOPS output is consumed via `sops -d --output-type ...
  | yq ...` and piped, never written to a temp file. If a temp file is unavoidable, use
  `mktemp -p /run/user/$(id -u)` and `trap 'shred -u "$tmp"' EXIT`.
- **No `eval` on user input.** Quote, validate, refuse.
- **Quote every expansion**: `"$var"`, `"$@"`, `"${arr[@]}"`. Unquoted expansions are a
  shellcheck error here.

## Skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [-h] <profile>

Renders the Ansible inventory for the given cohort profile.
EOF
}

main() {
    [[ $# -eq 0 ]] && { usage; exit 64; }

    while getopts ":h" opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            *) usage; exit 64 ;;
        esac
    done
    shift $((OPTIND - 1))

    local profile="$1"
    validate_profile "$profile"
    render_inventory "$profile"
}

validate_profile() {
    local p="$1"
    case "$p" in
        vpn-p0|vpn-p1p2|vpn-fullstack) return 0 ;;
        *) printf 'unknown profile: %s\n' "$p" >&2; exit 65 ;;
    esac
}

render_inventory() {
    local profile="$1"
    # ... no secrets touch disk ...
}

main "$@"
```

## Exit codes — follow sysexits.h

| Code | Meaning |
|---|---|
| 0 | success |
| 64 | usage error |
| 65 | data format error |
| 66 | input file missing |
| 69 | service unavailable (e.g., SOPS, cloud API) |
| 70 | internal error |
| 78 | configuration error |

Operators read these in CI. `exit 1` everywhere is a smell.

## Logging

- `printf` over `echo` for anything with variables (echo flag handling varies).
- stderr for human-readable status, stdout for machine output that another tool will
  parse. Never mix them.
- No emoji, no ANSI colors when `[[ ! -t 2 ]]` (CI output goes to logs that mangle them).

## Traps

```bash
cleanup() {
    local rc=$?
    [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    return "$rc"
}
trap cleanup EXIT
```

Trap **EXIT**, not just **ERR**. ERR alone misses signal-driven exits.

## Concurrency

- Lock with `flock` on a known path, e.g., `/run/lock/vpn-deploy-${profile}.lock`. Don't
  hand-roll PID files.
- No parallel `terraform apply` for the same provider root. Use the lock.

## Don'ts

- **No `set -x` in production scripts** — leaks secrets to logs. Use `${DEBUG:-}` opt-in.
- **No `which`** — use `command -v`.
- **No `ls | xargs`** — globs and `find -print0 | xargs -0`.
- **No subshell-on-error patterns** like `cmd && other || fallback` — confusing. Use
  explicit `if`.
- **No `[ ]`** — always `[[ ]]` in bash code.

## Testing

- shellcheck via `make ci-fast`.
- Optional `bats` tests live alongside the script: `scripts/render-inventory.bats`. Not
  every script needs them; render-inventory and validate-secrets do.

## See also

- `scripts/CLAUDE.md` — conventions per script
- `[[security-review]]` — what cannot leak through scripts
- `[[conventional-commit]]` — commit format for `scripts(...)` scope
