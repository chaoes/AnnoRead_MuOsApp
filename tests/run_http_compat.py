#!/usr/bin/env python3
"""Start the local HTTP fixture on an ephemeral port and run its Lua tests."""
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path


root = Path(__file__).resolve().parents[1]
lua = shutil.which("luajit")
if not lua:
    raise SystemExit("luajit is required to run HTTP compatibility tests")

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]

server = subprocess.Popen(
    [sys.executable, str(root / "tests" / "http_compat_server.py"), str(port)],
    cwd=root,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
)
try:
    ready = False
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if server.poll() is not None:
            raise RuntimeError("HTTP fixture exited early: " + server.stderr.read().decode("utf-8", "replace"))
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                ready = True
                break
        except OSError:
            time.sleep(0.05)
    if not ready:
        raise RuntimeError("HTTP fixture did not become ready")

    env = os.environ.copy()
    env["ANNO_TEST_URL"] = "http://127.0.0.1:" + str(port)
    completed = subprocess.run([lua, "tests/test_http_compat.lua"], cwd=root, env=env)
    if completed.returncode:
        raise SystemExit(completed.returncode)
    raise SystemExit(subprocess.run([lua, "tests/test_http_view_requests.lua"], cwd=root, env=env).returncode)
finally:
    server.terminate()
    try:
        server.wait(timeout=2)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
