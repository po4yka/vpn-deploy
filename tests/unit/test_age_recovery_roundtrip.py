"""Roundtrip tests for scripts/age-recovery-combine.sh.

Verifies that any 3-of-5 Shamir shares reconstruct the correct age private
key. Tests two different 3-share subsets to confirm any-3-of-5 semantics.

The script reads shares from stdin (ssss-combine -t T -Q reads interactively).
We feed the T share lines via subprocess stdin.
"""
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "age-recovery-combine.sh"
SHARES_DIR = REPO_ROOT / "tests" / "fixtures" / "age-recovery-shares"
AGE_KEY_FILE = REPO_ROOT / "tests" / "fixtures" / "age-test.key"

# The expected AGE secret key extracted from the test fixture
EXPECTED_KEY = "AGE-SECRET-KEY-1V070XMWMW3TKQZFQCEUK8ZV82VFRD4EG8Z7LHECG5VP7CXP7XP2QMMQY9M"


def _load_share(n: int) -> str:
    """Load share N (1-indexed), stripping trailing whitespace."""
    return (SHARES_DIR / f"share-{n}.txt").read_text().strip()


def _combine(shares: list[str]) -> subprocess.CompletedProcess:
    """Run age-recovery-combine.sh with the given share strings as stdin."""
    threshold = len(shares)
    stdin_text = "\n".join(shares) + "\n"
    return subprocess.run(
        ["bash", str(SCRIPT), str(threshold)],
        input=stdin_text,
        capture_output=True,
        text=True,
        check=False,
    )


def test_combine_shares_1_3_5():
    """Shares 1, 3, 5 reconstruct the correct key."""
    shares = [_load_share(1), _load_share(3), _load_share(5)]
    result = _combine(shares)
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"
    assert EXPECTED_KEY in result.stdout, (
        f"Expected key not found in output.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_combine_shares_2_4_5():
    """Shares 2, 4, 5 also reconstruct the correct key (any-3-of-5)."""
    shares = [_load_share(2), _load_share(4), _load_share(5)]
    result = _combine(shares)
    assert result.returncode == 0, f"stderr: {result.stderr}\nstdout: {result.stdout}"
    assert EXPECTED_KEY in result.stdout, (
        f"Expected key not found in output.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_combine_output_matches_age_key_file():
    """The reconstructed key string matches what is in age-test.key."""
    key_file_text = AGE_KEY_FILE.read_text()
    key_line = next(
        line for line in key_file_text.splitlines() if line.startswith("AGE-SECRET-KEY-")
    )
    assert key_line == EXPECTED_KEY, f"Fixture mismatch: {key_line!r} != {EXPECTED_KEY!r}"

    shares = [_load_share(1), _load_share(2), _load_share(3)]
    result = _combine(shares)
    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert key_line in result.stdout, result.stdout
