"""Check the shipped helper, its private handshake and its bundled child without a live Codex connection."""
from pathlib import Path
import json
import os
import selectors
import subprocess
import tempfile
import time

app = Path(__file__).resolve().parents[1] / "build/Packpier.app/Contents"
helper = app / "Helpers/packpier-codex-loader"
node = app / "Helpers/node"

with tempfile.TemporaryDirectory() as tmp:
    store = Path(tmp) / "plugins"
    (store / "packages").mkdir(parents=True)
    (store / "app-state.json").write_text(json.dumps({"enabled": False, "disabledPackageIDs": []}))
    with subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          env={**os.environ, "PATH": "/usr/bin:/bin", "HOME": tmp}) as child:
        try:
            request = {"id": 1, "method": "initialize", "params": {"libraryDirectory": str(store)}}
            child.stdin.write(json.dumps(request).encode() + b"\n")
            child.stdin.flush()
            deadline = time.monotonic() + 10
            pending = b""
            with selectors.DefaultSelector() as reader:
                reader.register(child.stdout, selectors.EVENT_READ)
                while True:
                    if not reader.select(max(0, deadline - time.monotonic())):
                        raise TimeoutError("Packpier loader did not acknowledge initialization")
                    chunk = os.read(child.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError("Packpier loader exited before initialization")
                    lines = (pending + chunk).split(b"\n")
                    pending = lines.pop()
                    reply = next((msg for msg in map(json.loads, lines) if msg.get("id") == 1), None)
                    if reply is not None:
                        break
            assert "result" in reply, reply.get("error")
            assert reply["result"]["enabled"] is False and isinstance(reply["result"]["packages"], list)
            processes = subprocess.check_output(["/bin/ps", "-axo", "ppid=,comm="], text=True)
            assert [str(child.pid), str(node)] in [row.split(None, 1) for row in processes.splitlines()]
            print("PASS installed loader replies and runs its bundled Node child with no system Node on PATH")
        finally:
            child.stdin.close()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
                raise
        assert child.returncode == 0, child.returncode
