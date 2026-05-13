#!/usr/bin/env bats
# Dry-run tests for scripts/blue-green.sh.
#
# Verifies that --dry-run exits 0 and triggers only read-only stub calls:
#   - output mentions "terraform plan"
#   - output mentions "--check"
#   - STUB_LOG does not contain: terraform apply, audit-log, sops --encrypt

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/blue-green.sh"
STUB_BIN="${REPO_ROOT}/tests/stubs/bin"

setup() {
  STUB_LOG="$(mktemp -t stub_log.XXXXXX)"
  FAKE_SOPS="$(mktemp -t prod_secrets.XXXXXX)"
  # blue-green.sh checks SOPS_FILE exists before reaching the dry-run branch
  export PATH="${STUB_BIN}:${PATH}"
  export STUB_LOG
  export BLUE_ENV="prod"
  export GREEN_ENV="green1"
  export PROVIDER="upcloud"
  export SOPS_FILE="${FAKE_SOPS}"
  export ANSIBLE_SSH_PRIVATE_KEY_FILE="${BATS_TEST_TMPDIR}/id_ed25519"
  export MAKE="true"
}

teardown() {
  rm -f "${STUB_LOG}" "${FAKE_SOPS}"
}

_run_dry() {
  run bash "${SCRIPT}" --dry-run --blue-env prod --green-env green1
}

@test "dry-run exits 0" {
  _run_dry
  assert_success
}

@test "dry-run output mentions terraform plan" {
  _run_dry
  assert_output --partial "terraform plan"
}

@test "dry-run output mentions --check (ansible check mode)" {
  _run_dry
  assert_output --partial "--check"
}

@test "dry-run STUB_LOG has no terraform apply" {
  _run_dry
  if [[ -s "${STUB_LOG}" ]]; then
    run grep -F "terraform apply" "${STUB_LOG}"
    assert_failure
  fi
}

@test "dry-run STUB_LOG has no audit-log" {
  _run_dry
  if [[ -s "${STUB_LOG}" ]]; then
    run grep -F "audit-log" "${STUB_LOG}"
    assert_failure
  fi
}

@test "dry-run STUB_LOG has no sops --encrypt" {
  _run_dry
  if [[ -s "${STUB_LOG}" ]]; then
    run grep -F -- "--encrypt" "${STUB_LOG}"
    assert_failure
  fi
}

@test "dry-run STUB_LOG has no sops call at all" {
  _run_dry
  if [[ -s "${STUB_LOG}" ]]; then
    run grep -F "sops" "${STUB_LOG}"
    assert_failure
  fi
}
