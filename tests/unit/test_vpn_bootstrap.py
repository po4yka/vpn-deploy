"""Drive the subscription delivery service end-to-end.

The service is shipped as a Jinja2 template. We render it with stable
test paths, import it as a module, and exercise the HTTP surface with a
plain urllib client. The point is to lock the contract that the
operator-facing helpers (issue-sub-token.sh / sub-reads.sh) implicitly
depend on:

  * sha256(token) is the on-disk key — plaintext never touches disk
  * /sub/ is long-lived, /bootstrap/ consumes on read
  * expired payloads return 410 (and /bootstrap/ purges)
  * revoked hashes return 410 and are re-read every request
  * one JSONL audit record per request with hash prefix (not full hash)
  * X-Real-IP is preferred over peer address
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import socket
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest
from jinja2 import Environment, FileSystemLoader, StrictUndefined

REPO_ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = (
    REPO_ROOT
    / "ansible"
    / "roles"
    / "subscription-host"
    / "templates"
    / "vpn-bootstrap.py.j2"
)


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def service(tmp_path):
    """Render the .j2 with test paths, import as a module, start the
    HTTPServer in a daemon thread, hand the test a small handle with
    helpers for placing tokens + reading audit records.
    """
    sub_dir = tmp_path / "vpn-subscription"
    reads_log = tmp_path / "reads.log"
    revoked_file = sub_dir / "revoked"
    port = _free_port()

    env = Environment(
        loader=FileSystemLoader(str(TEMPLATE.parent)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )
    rendered = env.get_template(TEMPLATE.name).render(
        subscription={
            "subscription_dir": str(sub_dir),
            "bootstrap_listen_addr": "127.0.0.1",
            "bootstrap_listen_port": port,
            "reads_log": str(reads_log),
            "revoked_file": str(revoked_file),
        }
    )
    py_path = tmp_path / "vpn_bootstrap.py"
    py_path.write_text(rendered)

    spec = importlib.util.spec_from_file_location("vpn_bootstrap_under_test", py_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    # Bring up the server in a background thread; main() blocks.
    server_holder: dict = {}

    def _serve():
        from http.server import ThreadingHTTPServer

        for route in ("bootstrap", "sub"):
            (sub_dir / route).mkdir(parents=True, exist_ok=True)
        reads_log.parent.mkdir(parents=True, exist_ok=True)
        revoked_file.parent.mkdir(parents=True, exist_ok=True)
        if not revoked_file.exists():
            revoked_file.touch(mode=0o600)
        srv = ThreadingHTTPServer(("127.0.0.1", port), module.Handler)
        server_holder["srv"] = srv
        srv.serve_forever()

    t = threading.Thread(target=_serve, daemon=True)
    t.start()
    # poll until the listener accepts
    for _ in range(50):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                break
        except OSError:
            time.sleep(0.02)
    else:
        raise RuntimeError("vpn-bootstrap test server failed to come up")

    class Handle:
        port = None
        sub_dir = None
        reads_log = None
        revoked_file = None

        def place(self, route: str, token: str, payload: bytes, *, expires=None):
            h = hashlib.sha256(token.encode()).hexdigest()
            (sub_dir / route / h).write_bytes(payload)
            if expires is not None:
                (sub_dir / route / f"{h}.meta").write_text(
                    json.dumps({"expires": expires})
                )

        def revoke(self, token: str):
            h = hashlib.sha256(token.encode()).hexdigest()
            with revoked_file.open("a") as fh:
                fh.write(h + "\n")

        def get(self, path, headers=None):
            req = urllib.request.Request(f"http://127.0.0.1:{port}{path}")
            if headers:
                for k, v in headers.items():
                    req.add_header(k, v)
            try:
                return urllib.request.urlopen(req, timeout=2)
            except urllib.error.HTTPError as exc:
                return exc

        def reads(self):
            if not reads_log.exists():
                return []
            out = []
            for line in reads_log.read_text().splitlines():
                line = line.strip()
                if line:
                    out.append(json.loads(line))
            return out

    h = Handle()
    h.port = port
    h.sub_dir = sub_dir
    h.reads_log = reads_log
    h.revoked_file = revoked_file
    yield h

    srv = server_holder.get("srv")
    if srv:
        srv.shutdown()
        srv.server_close()


# ---------------------------------------------------------------------------
# /sub/ — long-lived, idempotent
# ---------------------------------------------------------------------------
def test_sub_serves_payload_and_audits_consumed(service):
    token = "abc12345abc12345"  # 16+ chars matches PATH_RE
    service.place("sub", token, b'{"outbound":"vless"}')

    resp = service.get(f"/sub/{token}")
    assert resp.status == 200
    body = resp.read()
    assert body == b'{"outbound":"vless"}'
    assert resp.headers["Content-Type"] == "application/json"
    assert resp.headers["Cache-Control"] == "no-store"
    assert resp.headers["Referrer-Policy"] == "no-referrer"

    rec = service.reads()
    assert len(rec) == 1
    assert rec[0]["route"] == "sub"
    assert rec[0]["outcome"] == "consumed"
    assert rec[0]["bytes"] == len(body)
    h = hashlib.sha256(token.encode()).hexdigest()
    assert rec[0]["token_prefix"] == h[:8]
    assert "token" not in rec[0]  # never log the plaintext


def test_sub_is_idempotent(service):
    token = "xyz98765xyz98765"
    service.place("sub", token, b"payload-A")
    assert service.get(f"/sub/{token}").read() == b"payload-A"
    assert service.get(f"/sub/{token}").read() == b"payload-A"
    assert len(service.reads()) == 2


# ---------------------------------------------------------------------------
# /bootstrap/ — single-use, atomic consume
# ---------------------------------------------------------------------------
def test_bootstrap_consumes_once(service):
    token = "aaaa1111bbbb2222"
    service.place("bootstrap", token, b"hello")

    resp = service.get(f"/bootstrap/{token}")
    assert resp.status == 200
    assert resp.read() == b"hello"

    resp2 = service.get(f"/bootstrap/{token}")
    assert resp2.status == 410

    recs = service.reads()
    assert [r["outcome"] for r in recs] == ["consumed", "unknown"]


def test_bootstrap_purges_meta_with_payload(service):
    token = "1111aaaa2222bbbb"
    service.place("bootstrap", token, b"payload", expires="2099-01-01")
    h = hashlib.sha256(token.encode()).hexdigest()

    assert service.get(f"/bootstrap/{token}").status == 200
    assert not (service.sub_dir / "bootstrap" / h).exists()
    assert not (service.sub_dir / "bootstrap" / f"{h}.meta").exists()


# ---------------------------------------------------------------------------
# Expiry
# ---------------------------------------------------------------------------
def test_sub_expired_returns_410_but_keeps_payload(service):
    token = "exp10000exp10000"
    service.place("sub", token, b"won't see this", expires=1700000000)  # 2023
    h = hashlib.sha256(token.encode()).hexdigest()

    resp = service.get(f"/sub/{token}")
    assert resp.status == 410
    # /sub/ leaves the payload alone — operator can bump .meta to re-enable
    assert (service.sub_dir / "sub" / h).exists()
    assert service.reads()[-1]["outcome"] == "expired"


def test_bootstrap_expired_returns_410_and_purges(service):
    token = "exp20000exp20000"
    service.place("bootstrap", token, b"payload", expires="2000-01-01")
    h = hashlib.sha256(token.encode()).hexdigest()

    assert service.get(f"/bootstrap/{token}").status == 410
    assert not (service.sub_dir / "bootstrap" / h).exists()
    assert not (service.sub_dir / "bootstrap" / f"{h}.meta").exists()
    assert service.reads()[-1]["outcome"] == "expired"


def test_expired_iso_with_timezone_offset(service):
    token = "iso10000iso10000"
    service.place("sub", token, b"x", expires="2000-01-01T00:00:00+00:00")
    assert service.get(f"/sub/{token}").status == 410
    assert service.reads()[-1]["outcome"] == "expired"


def test_unparseable_expires_falls_back_to_serving(service):
    """Garbled .meta must not deny service. The operator hitting a typo
    in expires shouldn't take the endpoint down for everyone."""
    token = "garb1000garb1000"
    service.place("sub", token, b"served")
    h = hashlib.sha256(token.encode()).hexdigest()
    (service.sub_dir / "sub" / f"{h}.meta").write_text('{"expires": "not-a-date"}')

    resp = service.get(f"/sub/{token}")
    assert resp.status == 200
    assert resp.read() == b"served"


# ---------------------------------------------------------------------------
# Revocation
# ---------------------------------------------------------------------------
def test_revoked_returns_410_and_does_not_serve(service):
    token = "rev10000rev10000"
    service.place("sub", token, b"payload")
    service.revoke(token)

    resp = service.get(f"/sub/{token}")
    assert resp.status == 410
    assert service.reads()[-1]["outcome"] == "revoked"


def test_revocation_is_live_no_restart_needed(service):
    """Adding a hash to revoked_file mid-traffic takes effect on the next
    request — no service reload."""
    token = "live1000live1000"
    service.place("sub", token, b"payload")

    assert service.get(f"/sub/{token}").status == 200

    service.revoke(token)
    assert service.get(f"/sub/{token}").status == 410


def test_revoked_file_with_comments_and_blanks(service):
    """The file is operator-edited; tolerate # comments and blank lines."""
    token = "cmt10000cmt10000"
    service.place("sub", token, b"payload")
    h = hashlib.sha256(token.encode()).hexdigest()
    service.revoked_file.write_text(
        f"# rotated on 2026-05-01\n\n{h}\n# trailing comment\n"
    )
    assert service.get(f"/sub/{token}").status == 410


# ---------------------------------------------------------------------------
# Unknown / shape errors
# ---------------------------------------------------------------------------
def test_unknown_token_returns_410_audit_unknown(service):
    token = "missing0missing0"
    resp = service.get(f"/sub/{token}")
    assert resp.status == 410
    assert service.reads()[-1]["outcome"] == "unknown"


def test_malformed_path_returns_404(service):
    resp = service.get("/something-else")
    assert resp.status == 404
    # 404 happens before route parsing — no audit record
    assert service.reads() == []


def test_short_token_rejected(service):
    # PATH_RE requires {16,64} — 8 chars must not parse
    resp = service.get("/sub/abcdefgh")
    assert resp.status == 404


def test_wrong_route_rejected(service):
    resp = service.get("/nope/abcdefgh01234567")
    assert resp.status == 404


# ---------------------------------------------------------------------------
# X-Real-IP forwarding
# ---------------------------------------------------------------------------
def test_x_real_ip_preferred_over_peer(service):
    token = "xri10000xri10000"
    service.place("sub", token, b"payload")
    service.get(f"/sub/{token}", headers={"X-Real-IP": "203.0.113.7"})

    rec = service.reads()[-1]
    assert rec["src_ip"] == "203.0.113.7"
    # peer is loopback — make sure we're not just reading from there
    assert rec["src_ip"] != "127.0.0.1"


def test_audit_record_shape_locked(service):
    """The downstream sub-reads.sh contract pins these exact keys."""
    token = "shp10000shp10000"
    service.place("sub", token, b"payload")
    service.get(f"/sub/{token}")
    rec = service.reads()[-1]

    assert set(rec.keys()) == {
        "ts",
        "iso",
        "route",
        "token_prefix",
        "outcome",
        "src_ip",
        "bytes",
    }
    assert isinstance(rec["ts"], int)
    assert isinstance(rec["bytes"], int)
    assert len(rec["token_prefix"]) == 8
