"""Dry-run tests for scripts/blue-green.sh.

Verifies that --dry-run exits 0 and triggers only read-only stub calls:
  - terraform plan is logged
  - ansible-playbook --check is logged
  - terraform apply is NOT logged
  - audit-log.sh append is NOT logged
  - sops --encrypt is NOT logged
"""
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
STUB_BIN = REPO_ROOT / "tests" / "stubs" / "bin"
SCRIPT = REPO_ROOT / "scripts" / "blue-green.sh"


def _run_dry(tmp_path: Path, extra_env: dict | None = None) -> subprocess.CompletedProcess:
    stub_log = tmp_path / "stub.log"
    # Provide a fake SOPS_FILE so the pre-dry-run file-existence check is skipped.
    # In dry-run mode the script never reads the file, but we still need the path
    # to exist because the check happens before the DRY_RUN branch.
    fake_sops = tmp_path / "prod.secrets.sops.yaml"
    fake_sops.touch()

    env = {
        **os.environ,
        "PATH": f"{STUB_BIN}:{os.environ['PATH']}",
        "STUB_LOG": str(stub_log),
        "BLUE_ENV": "prod",
        "GREEN_ENV": "green1",
        "PROVIDER": "upcloud",
        "SOPS_FILE": str(fake_sops),
        # Not required in dry-run but set to avoid any env-var guard that
        # fires before we reach the dry-run branch.
        "ANSIBLE_SSH_PRIVATE_KEY_FILE": str(tmp_path / "id_ed25519"),
        # Prevent make calls from going anywhere.
        "MAKE": "true",
    }
    if extra_env:
        env.update(extra_env)

    return subprocess.run(
        ["bash", str(SCRIPT), "--dry-run", "--blue-env", "prod", "--green-env", "green1"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_dry_run_exits_zero(tmp_path: Path):
    result = _run_dry(tmp_path)
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"


def test_dry_run_output_mentions_terraform_plan(tmp_path: Path):
    result = _run_dry(tmp_path)
    combined = result.stdout + result.stderr
    assert "terraform plan" in combined, combined


def test_dry_run_output_mentions_ansible_check(tmp_path: Path):
    result = _run_dry(tmp_path)
    combined = result.stdout + result.stderr
    assert "--check" in combined, combined


def test_dry_run_no_terraform_apply(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "terraform apply" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_audit_log_append(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "audit-log" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_sops_encrypt(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "--encrypt" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_sops_decrypt_in_stub_log(tmp_path: Path):
    """sops --decrypt must not appear in STUB_LOG (no real sops call in dry-run)."""
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "sops" not in log_text, f"stub log: {log_text}"
