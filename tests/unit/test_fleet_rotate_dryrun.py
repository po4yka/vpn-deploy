"""Dry-run tests for scripts/fleet-rotate.sh.

Verifies that --dry-run exits 0 and is hermetic:
  - STUB_LOG never sees terraform apply, sops --encrypt, gh release create
  - The script iterates all plan entries (each id visible in output)
"""
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
STUB_BIN = REPO_ROOT / "tests" / "stubs" / "bin"
SCRIPT = REPO_ROOT / "scripts" / "fleet-rotate.sh"
PLAN = REPO_ROOT / "tests" / "fixtures" / "fleet-plan-sample.yaml"


def _run_dry(tmp_path: Path) -> subprocess.CompletedProcess:
    stub_log = tmp_path / "stub.log"
    env = {
        **os.environ,
        "PATH": f"{STUB_BIN}:{os.environ['PATH']}",
        "STUB_LOG": str(stub_log),
    }
    return subprocess.run(
        ["bash", str(SCRIPT), "--plan", str(PLAN), "--dry-run"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_dry_run_exits_zero(tmp_path: Path):
    result = _run_dry(tmp_path)
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"


def test_dry_run_shows_plan_id(tmp_path: Path):
    result = _run_dry(tmp_path)
    combined = result.stdout + result.stderr
    assert "2026-05-test-rotation" in combined, combined


def test_dry_run_iterates_both_entries(tmp_path: Path):
    """Each rotation entry must appear in the output."""
    result = _run_dry(tmp_path)
    combined = result.stdout + result.stderr
    # The fixture has two entries: upcloud:prod → prod-2026-05 and hetzner:prod → prod-2026-05
    assert "upcloud" in combined, combined
    assert "hetzner" in combined, combined


def test_dry_run_no_terraform_apply(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "terraform apply" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_sops_encrypt(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "--encrypt" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_gh_release_create(tmp_path: Path):
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "release create" not in log_text, f"stub log: {log_text}"


def test_dry_run_no_audit_log_append(tmp_path: Path):
    """audit-log.sh append must not be called in dry-run mode."""
    _run_dry(tmp_path)
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert "audit-log" not in log_text, f"stub log: {log_text}"
