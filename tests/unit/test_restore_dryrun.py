"""Dry-run tests for scripts/restore.sh.

Verifies that --dry-run exits 0, prints procedural steps, and does not
invoke any destructive stub operations.
"""
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
STUB_BIN = REPO_ROOT / "tests" / "stubs" / "bin"
SCRIPT = REPO_ROOT / "scripts" / "restore.sh"


def _run(tmp_path: Path, *extra_args: str) -> subprocess.CompletedProcess:
    stub_log = tmp_path / "stub.log"
    env = {
        **os.environ,
        "PATH": f"{STUB_BIN}:{os.environ['PATH']}",
        "STUB_LOG": str(stub_log),
    }
    return subprocess.run(
        ["sh", str(SCRIPT), "--dry-run", "--env", "prod", "--provider", "upcloud", *extra_args],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


# ---------------------------------------------------------------------------
# Path A tests
# ---------------------------------------------------------------------------

def test_path_a_exits_zero(tmp_path: Path):
    result = _run(tmp_path, "--path-a")
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"


def test_path_a_mentions_env(tmp_path: Path):
    result = _run(tmp_path, "--path-a")
    combined = result.stdout + result.stderr
    assert "prod" in combined, combined


def test_path_a_mentions_procedure_steps(tmp_path: Path):
    result = _run(tmp_path, "--path-a")
    combined = result.stdout + result.stderr
    # Path A must mention the key procedural steps from the runbook
    assert "make init" in combined or "make deploy" in combined, combined
    assert "Path A" in combined, combined


def test_path_a_no_destructive_stub_calls(tmp_path: Path):
    _run(tmp_path, "--path-a")
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert log_text == "", f"unexpected stub calls in dry-run: {log_text}"


# ---------------------------------------------------------------------------
# Path B tests
# ---------------------------------------------------------------------------

def test_path_b_exits_zero(tmp_path: Path):
    result = _run(tmp_path, "--path-b")
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"


def test_path_b_mentions_restic(tmp_path: Path):
    result = _run(tmp_path, "--path-b")
    combined = result.stdout + result.stderr
    assert "restic" in combined, combined


def test_path_b_mentions_path_b(tmp_path: Path):
    result = _run(tmp_path, "--path-b")
    combined = result.stdout + result.stderr
    assert "Path B" in combined, combined


def test_path_b_no_destructive_stub_calls(tmp_path: Path):
    _run(tmp_path, "--path-b")
    stub_log = tmp_path / "stub.log"
    if stub_log.exists():
        log_text = stub_log.read_text()
        assert log_text == "", f"unexpected stub calls in dry-run: {log_text}"


# ---------------------------------------------------------------------------
# Error-case tests
# ---------------------------------------------------------------------------

def test_missing_env_flag_exits_nonzero(tmp_path: Path):
    stub_log = tmp_path / "stub.log"
    env = {**os.environ, "PATH": f"{STUB_BIN}:{os.environ['PATH']}", "STUB_LOG": str(stub_log)}
    result = subprocess.run(
        ["sh", str(SCRIPT), "--dry-run", "--path-a"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0


def test_missing_path_flag_exits_nonzero(tmp_path: Path):
    stub_log = tmp_path / "stub.log"
    env = {**os.environ, "PATH": f"{STUB_BIN}:{os.environ['PATH']}", "STUB_LOG": str(stub_log)}
    result = subprocess.run(
        ["sh", str(SCRIPT), "--dry-run", "--env", "prod"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
