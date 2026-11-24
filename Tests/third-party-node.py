"""Load an explicitly approved, local ZIP through the manager's private loader protocol."""
import json
import os
from pathlib import Path
from queue import Queue
import shutil
import subprocess
import tempfile
from threading import Thread
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
system_node = shutil.which("node")
assert system_node and int(subprocess.check_output([system_node, "-p", "process.versions.node.split('.')[0]"])) >= 22
plugin = "fixture-node-service"
source = """
export function activate({rpc, dataDirectory}) {
  rpc.handle('stall', () => new Promise(() => {}));
  rpc.handle('echo', ({number}) => {
    rpc.emit('sample', number);
    return {number, dataDirectory, pid: process.pid};
  });
}
"""


def zip_package(file, contents):
    with ZipFile(file, "w") as z:
        z.writestr("plugin/package.json", json.dumps({"name": plugin, "version": "1.0.0", "type": "module",
                   "packpier": {"apiVersion": 3, "entrypoints": {"node": "./src/backend.js"}}}))
        z.writestr("plugin/src/backend.js", contents)


def package(state, name):
    return next(p for p in state["packages"] if p["id"] == name)


with tempfile.TemporaryDirectory(prefix="packpier-node-tests-") as temporary:
    tmp = Path(temporary)
    helper = tmp / "Contents/Helpers/packpier-codex-loader"
    helper.parent.mkdir(parents=True)
    shutil.copy2(root / "build/packpier-loader", helper)
    runtime = tmp / "Contents/Resources/NodeRunner"
    runtime.mkdir(parents=True)
    shutil.copy2(root / "Resources/NodeRunner/runner.mjs", runtime)
    library = tmp / "library"
    for name in ("p-sign", "prism", "custom-background"):
        path = library / "packages" / name
        path.mkdir(parents=True)
        (path / "package.json").write_text(json.dumps({"name": name, "version": "1.0.0", "packpier": {
            "apiVersion": 3, "entrypoints": {"node": "unused.js"}}}))
    (library / "app-state.json").write_text('{"enabled":true}')
    env = dict(os.environ, HOME=str(tmp), CFFIXED_USER_HOME=str(tmp), TMPDIR=str(tmp), PACKPIER_NODE=system_node)
    command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", helper]
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env) as child:
        lines = Queue()

        def read():
            for line in child.stdout:
                lines.put(json.loads(line))
            lines.put(None)

        reader = Thread(target=read, daemon=True)
        reader.start()
        events = []
        sequence = 0

        def request(command_name, expect_error=False, **params):
            global sequence
            sequence += 1
            child.stdin.write(json.dumps({"id": sequence, "method": command_name, "params": params}) + "\n")
            child.stdin.flush()
            while True:
                reply = lines.get(timeout=12)
                assert reply is not None, "Unexpected loader exit"
                if reply.get("event") == "nodeEvent":
                    events.append(reply["data"])
                if reply.get("id") == sequence:
                    assert ("error" in reply) == expect_error, reply
                    return reply.get("result")

        try:
            initial = request("initialize", libraryDirectory=str(library))
            assert all(p["node"]["running"] is False and "validationError" not in p for p in initial["packages"])
            zip_path = tmp / "demo.zip"
            zip_package(zip_path, source)
            installed = package(request("installLocalPackage", sourcePath=str(zip_path)), plugin)
            token = installed["node"]["authorizationID"]
            assert not installed["node"]["running"] and installed["availableActions"]["authorizeNode"]
            request("callNodePackage", True, packageID=plugin, method="echo")
            request("authorizeNodePackage", True, packageID=plugin, authorizationID="stale")
            ready = package(request("authorizeNodePackage", packageID=plugin, authorizationID=token), plugin)
            assert ready["node"]["authorized"] and ready["node"]["running"], ready
            result = request("callNodePackage", packageID=plugin, method="echo", parameters={"number": 42})["value"]
            assert result["number"] == 42 and Path(result["dataDirectory"]).parent == library / "node-data"
            assert events == [{"plugin": plugin, "name": "sample", "payload": 42}]
            off = package(request("setPackageEnabled", packageID=plugin, enabled=False), plugin)
            assert not off["node"]["running"]
            assert subprocess.run(["/bin/ps", "-p", str(result["pid"])], stdout=subprocess.DEVNULL).returncode == 1
            on = package(request("setPackageEnabled", packageID=plugin, enabled=True), plugin)
            assert on["node"]["running"]
            request("callNodePackage", True, packageID=plugin, method="stall", parameters={})
            stalled = package(request("getState"), plugin)
            assert not stalled["node"]["running"] and "timed out" in stalled["validationError"]
            zip_package(Path(installed["directory"]) / ".packpier-source.zip", source + "\n// another build")
            changed = package(request("reloadPackages"), plugin)
            assert not changed["node"]["running"] and changed["node"]["authorizationID"] != token
            request("authorizeNodePackage", True, packageID=plugin, authorizationID=token)
            archive = Path(installed["directory"]) / ".packpier-source.zip"
            with ZipFile(archive, "a") as z:
                z.writestr("plugin/../escaped-file", "unexpected")
            malformed = package(request("reloadPackages"), plugin)
            assert malformed.get("validationError") and not malformed["node"]["running"]
            assert not (tmp / "escaped-file").exists()
            plan = request("getWindowPlan")
            assert {p["id"] for p in plan["packages"]} == {"p-sign", "prism", "custom-background"}
            assert all(not p["node"]["running"] for p in request("getState")["packages"])
        finally:
            child.stdin.close()
            child.wait(timeout=8)
            reader.join(timeout=2)
        assert child.returncode == 0
print("PASS native built-ins, Node ZIP approval, init/call/event, cleanup and content-bound reauthorization")
