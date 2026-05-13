# tests/stubs — command stubs for test isolation

Stubs replace real provider CLIs and infrastructure tools during unit and
dry-run tests. They are POSIX sh scripts that echo their invocation and
exit 0, allowing test code to exercise orchestration logic without any
real infrastructure calls.

## PATH-prepend discipline

Always prepend the stubs directory to PATH before running tests:

```sh
export PATH="${REPO_ROOT}/tests/stubs/bin:${PATH}"
```

where `REPO_ROOT` is the repository root. This shadows real binaries only
for the duration of the test process.

## STUB_LOG — capturing invocations

Set `STUB_LOG` to a file path to record every stub invocation:

```sh
export STUB_LOG=/tmp/stublog
PATH=tests/stubs/bin:$PATH ansible-playbook site.yml
tail /tmp/stublog
# STUB: ansible-playbook site.yml
```

When `STUB_LOG` is unset, stubs write to `/dev/null` (silent).

## Stub behaviours

| Stub | Special behaviour |
|------|-------------------|
| `terraform` | `output -json` → cats `tests/fixtures/tf-output-sample.json`; `output -raw <key>` → extracts value from fixture; all other subcommands echo + exit 0 |
| `ansible-playbook` | echo + exit 0 |
| `sops` | `--decrypt` → copies `tests/fixtures/secrets-sample.yml` to target or stdout; `--encrypt` → no-op; else echo + exit 0 |
| `curl` | `api.github.com/repos/*/releases/latest` → `{"tag_name":"vpnd-v0.1.0"}`; `ifconfig.me` / `ipv4.icanhazip.com` → `198.51.100.10`; else echo + exit 0 |
| `gh` | echo + exit 0 |
| `upcloud` `hcloud` `vultr` | echo + exit 0 |

## Adding a new stub

1. Create `tests/stubs/bin/<name>` with this template:

   ```sh
   #!/bin/sh
   set -eu

   STUB_LOG="${STUB_LOG:-/dev/null}"
   printf 'STUB: <name> %s\n' "$*" >&2
   printf 'STUB: <name> %s\n' "$*" >> "${STUB_LOG}"
   exit 0
   ```

2. Make it executable: `chmod 755 tests/stubs/bin/<name>`

3. Keep it under 30 lines and source nothing.

4. Run shellcheck: `shellcheck -s sh tests/stubs/bin/<name>`

5. Add the stub to the table above.

## Rules

- Stubs are NEVER on the production PATH — only in test contexts.
- Each stub must `set -eu` (POSIX) and source no other file.
- No bash-isms: use `[ ]` not `[[ ]]`, `printf` not `echo -e`.
- shellcheck `-s sh` must pass with zero warnings on every stub.
