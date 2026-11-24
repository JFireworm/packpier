"""Exercise the packaged loader with an isolated library and no access to live network endpoints."""
from pathlib import Path
import json
import os
import plistlib
import selectors
import shutil
import subprocess
import tempfile
import time

app = Path(__file__).resolve().parents[1] / "build" / os.environ.get("PACKPIER_ARCH", "") / "Packpier.app/Contents"
helper = app / "Helpers/packpier-codex-loader"


def check_bundle():
    assert {f.name for f in (app / "Helpers").iterdir()} == {helper.name}
    resources = app / "Resources"
    assert {f.name for f in (resources / "WindowHost").iterdir()} == {"window-effects.js"}
    assert (resources / "WindowHost/window-effects.js").read_bytes() == (
        app.parents[1] / "Renderer/window-effects.iife.js").read_bytes()
    for retired in ("Licenses/Node.txt", "window-effects.mjs"):
        assert not (resources / retired).exists(), retired
    assert "PackpierNodeVersion" not in plistlib.loads((app / "Info.plist").read_bytes())


def reply_to(child, pending, request):
    child.stdin.write(json.dumps(request).encode() + b"\n")
    child.stdin.flush()
    deadline = time.monotonic() + 10
    with selectors.DefaultSelector() as reader:
        reader.register(child.stdout, selectors.EVENT_READ)
        while time.monotonic() < deadline:
            while (end := pending.find(b"\n")) >= 0:
                reply = json.loads(pending[:end])
                del pending[:end + 1]
                if reply.get("id") == request["id"]:
                    assert "result" in reply, reply.get("error")
                    return reply["result"]
            if not reader.select(max(0, deadline - time.monotonic())):
                break
            chunk = os.read(child.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("Packpier loader exited before replying")
            pending.extend(chunk)
    raise TimeoutError(f"Packpier loader did not reply to {request['method']}")


def check_processes(parent):
    rows = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid=,comm="], text=True)
    children = {}
    for row in rows.splitlines():
        pid, ppid, command = row.split(None, 2)
        children.setdefault(int(ppid), []).append((int(pid), command))
    pending = list(children.get(parent, ()))
    while pending:
        pid, command = pending.pop()
        assert Path(command).name not in {"node", "nodejs", "window-host.mjs"}, command
        pending.extend(children.get(pid, ()))


def run_case(tmp, enabled, existing_conflict, blocker=None):
    store = Path(tmp) / "library"
    packages = store / "packages"
    order = ["p-sign", "prism", "third-party-fixture", "custom-background"]
    # An installed, switched-off Node package must not start a worker alongside the built-ins.
    disabled = [order[2]]
    for name in order:
        directory = packages / name
        directory.mkdir(parents=True)
        manifest = directory / "package.json"
        if name == order[2]:
            adapter = {"apiVersion": 3, "entrypoints": {"renderer": "renderer.js"}}
            if enabled:
                adapter["entrypoints"]["node"] = "backend.js"
            manifest.write_text(json.dumps({"name": name, "version": "1.0.0", "packpier": adapter}))
        else:
            shutil.copyfile(app / "Resources/BundledPlugins" / name / "package.json", manifest)
    (store / "app-state.json").write_text(json.dumps({"enabled": enabled, "disabledPackageIDs": disabled}))
    (store / "package-settings.json").write_text(json.dumps({
        "schemaVersion": 1, "packages": {name: {"priorityOverride": i * 16} for i, name in enumerate(order)}
    }))
    before = {p: p.read_bytes() for p in store.rglob("*") if p.is_file()}
    command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", helper]
    env = {**os.environ, "PATH": "/usr/bin:/bin", "CFFIXED_USER_HOME": tmp, "HOME": tmp}
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env) as child:
        pending = bytearray()
        try:
            state = reply_to(child, pending, {"id": 1, "method": "initialize", "params": {"libraryDirectory": str(store)}})
            assert state["enabled"] is enabled and state["disabledPackageIDs"] == disabled
            assert [package["id"] for package in state["packages"]] == order
            issues = {p["id"]: p["validationError"] for p in state["packages"] if "validationError" in p}
            assert not issues, issues
            if enabled:
                plan = reply_to(child, pending, {"id": 101, "method": "getWindowPlan"})
                assert [p["id"] for p in plan["packages"]] == ["p-sign", "prism", "custom-background"]
            idle_status = "loaderConflict" if existing_conflict else "waitingForCDP"
            expected = "loaderConflict" if blocker else (idle_status if enabled else "disabled")
            for request_id in range(2, 27):
                check_processes(child.pid)
                state = reply_to(child, pending, {"id": request_id, "method": "getState"})
                if state["status"]["kind"] == expected:
                    break
                time.sleep(0.2)
            assert state["status"]["kind"] == expected, state["status"]
            assert not state["windowEffects"]["mounted"] and not state["windowEffects"]["windows"]
            if blocker:
                assert state["status"]["message"] == "另一个加载器正在运行"
                blocker.terminate()
                blocker.wait(timeout=5)
                expected = idle_status
            # Observe a second polling interval as well as initialization.
            for _ in range(6):
                time.sleep(0.4)
                check_processes(child.pid)
            state = reply_to(child, pending, {"id": 100, "method": "getState"})
            assert state["status"]["kind"] == expected and not state["windowEffects"]["mounted"]
        finally:
            child.stdin.close()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
                raise
        assert child.returncode == 0, child.returncode
    assert all(p.read_bytes() == data for p, data in before.items()), "Existing package settings changed"
    print(f"PASS packaged loader, {expected}, four package settings preserved, no Node child observed")


check_bundle()
processes = subprocess.check_output(["/bin/ps", "-axww", "-o", "uid=,command="], text=True)
existing_conflict = any(
    "window-host.mjs" in command or
    any(command.endswith(suffix) or suffix + " " in command for suffix in (
        "/Contents/MacOS/Packpier", "/packpier-codex-loader", "/codex-tweaks-backend")) or
    ("/Packpier" in command and "/Contents/Helpers/node" in command)
    for uid, command in (line.split(maxsplit=1) for line in processes.splitlines() if line.strip())
    if int(uid) == os.getuid() and command.startswith("/")
    and not Path(command.split()[0]).name in {"bash", "zsh", "sh"}
)
for enabled in (False, True):
    with tempfile.TemporaryDirectory(prefix="packpier-packaged-") as tmp:
        run_case(tmp, enabled, existing_conflict)
with tempfile.TemporaryDirectory(prefix="packpier-conflict-") as tmp:
    fixture = Path(tmp) / "packpier-codex-loader"
    shutil.copy("/bin/sleep", fixture)
    with subprocess.Popen([fixture, "30"]) as blocker:
        try:
            run_case(tmp, True, existing_conflict, blocker)
        finally:
            if blocker.poll() is None:
                blocker.terminate()
                blocker.wait(timeout=5)
    if existing_conflict:
        print("PASS competing loader reported while another Packpier process remained active")
    else:
        print("PASS competing loader reported and normal discovery resumed after it exited")
