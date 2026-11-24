"""Check ordering, persistence and protocol behavior using an isolated Packpier store."""
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parents[1]
binary = root / "build/packpier-loader"


def session(folder, *commands):
    lines = [("initialize", {"libraryDirectory": str(folder)}), *commands]
    batch = "".join(json.dumps({"id": n, "method": name, "params": args}) + "\n"
                    for n, (name, args) in enumerate(lines))
    result = subprocess.run([binary], input=batch, capture_output=True, text=True,
                            timeout=8, check=True)
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    replies = [reply for reply in replies if "event" not in reply]
    assert [reply["id"] for reply in replies] == list(range(len(lines)))
    return replies


def ids(reply):
    return [item["id"] for item in reply["result"]["packages"]]


if __name__ == "__main__":
    with TemporaryDirectory() as private:
        folder = Path(private)
        for name, priority, deps in [("alpha", 3, {}), ("beta", -2, {"alpha": "*"}), ("sign", 0, {})]:
            package = folder / "packages" / name
            package.mkdir(parents=True)
            key = "codexTweaks" if name == "beta" else "packpier"
            (package / "package.json").write_text(json.dumps({
                "name": name, "version": "1.0.0", key: {
                    "apiVersion": 3, "priority": priority, "packageDependencies": deps}}))
        (folder / "package-settings.json").write_text('{"schemaVersion":1,"packages":{"beta":{"note":"keep"}}}')
        initial, invalid, moved, disabled = session(
            folder, ("setPackageOrder", {"packageIDs": ["beta", "alpha", "sign"]}),
            ("setPackageOrder", {"packageIDs": ["alpha", "beta", "sign"]}),
            ("setPackageEnabled", {"packageID": "beta", "enabled": False}))
        assert ids(initial) == ["sign", "alpha", "beta"]
        assert "error" in invalid
        assert ids(moved) == ["alpha", "beta", "sign"]
        assert disabled["result"]["disabledPackageIDs"] == ["beta"]
        reopened = session(folder)[0]
        assert reopened["result"] == disabled["result"]
        assert json.loads((folder / "package-settings.json").read_text())["packages"]["beta"]["note"] == "keep"
        assert reopened["result"]["status"]["kind"] == "disabled"
        enabled = session(folder, ("setEnabled", {"enabled": True}))[-1]
        # A bare development loader has no window host resources, so it reports the host wait.
        assert enabled["result"]["status"]["kind"] == "waitingForHost"
    with TemporaryDirectory() as private:
        folder = Path(private)
        deps = {"p-sign": {}, "prism": {"p-sign": "*"}, "custom-background": {"prism": "*"}}
        for name, dependencies in deps.items():
            package = folder / "packages" / name
            package.mkdir(parents=True)
            (package / "package.json").write_text(json.dumps({
                "name": name, "version": "1.0.0",
                "packpier": {"apiVersion": 3, "packageDependencies": dependencies},
            }))
        _, _, blocked, empty, restored, ready = session(
            folder, ("setEnabled", {"enabled": True}),
            ("setPackageEnabled", {"packageID": "p-sign", "enabled": False}), ("getWindowPlan", {}),
            ("setPackageEnabled", {"packageID": "p-sign", "enabled": True}), ("getWindowPlan", {}))
        assert ids(blocked) == list(deps) and blocked["result"]["disabledPackageIDs"] == ["p-sign"]
        assert set(blocked["result"]["packagePayloadErrors"]) == {"prism", "custom-background"}
        assert empty["result"]["packages"] == []
        assert session(folder, ("getWindowEffects", {}))[-1]["result"] == {"enabled": True, "packages": []}
        assert restored["result"]["packagePayloadErrors"] == {} and ids(ready) == list(deps)
        manifest = folder / "packages" / "prism" / "package.json"
        edited = json.loads(manifest.read_text())
        edited["packpier"]["packageDependencies"] = {"missing": "*"}
        manifest.write_text(json.dumps(edited))
        affected, available = session(folder, ("getWindowPlan", {}))
        assert ids(available) == ["p-sign"]
        assert set(affected["result"]["packagePayloadErrors"]) == {"prism", "custom-background"}
        assert affected["result"]["disabledPackageIDs"] == []
    print("PASS independent process, legacy/current manifests, dependency order, enable state and restart")

    with TemporaryDirectory() as private:
        folder = Path(private)
        builtin = ["p-sign", "prism", "custom-background"]
        custom = "packpier-ready-badge"
        order = ["p-sign", "prism", custom, "custom-background"]
        packages = folder / "packages"
        for name in order:
            # Resolve the requested id from its manifest, even if the folder's name differs.
            path = packages / ("renamed-package" if name == custom else name)
            path.mkdir(parents=True)
            (path / "package.json").write_text(json.dumps({"name": name, "version": "1.0.0", "packpier": {"apiVersion": 3}}))
        prefs = folder / "package-settings.json"
        app = folder / "app-state.json"
        settings = {name: {"priorityOverride": i * 16, "note": "keep"} for i, name in enumerate(order)}
        prefs.write_text(json.dumps({"packages": settings, "schemaVersion": 1}))
        app.write_text(json.dumps({"enabled": True, "knownPackageIDs": order, "disabledPackageIDs": [custom, "prism"]}))
        user_data = folder / "node-data" / "example"
        user_data.mkdir(parents=True)
        (user_data / "preferences.json").write_bytes(b"keep existing data")
        def deletion(plugin):
            return ("deletePackage", {"packageID": plugin})
        current, *protected, deleted, repeated = session(folder, *map(deletion, builtin), deletion(custom), deletion(custom))
        assert ids(current) == order
        assert all(reply["error"]["message"] == "内置插件不能删除。" for reply in protected)
        assert ids(deleted) == ids(repeated) == builtin
        assert not (packages / "renamed-package").exists()
        assert deleted["result"]["disabledPackageIDs"] == ["prism"]
        assert json.loads(app.read_text())["knownPackageIDs"] == builtin
        assert json.loads(prefs.read_text())["packages"] == {name: settings[name] for name in builtin}
        assert ids(session(folder)[0]) == builtin
        assert (user_data / "preferences.json").read_bytes() == b"keep existing data"

        pending = folder / ".packpier-removing"
        pending.mkdir()
        (pending / "package.json").write_text(json.dumps({"name": custom, "version":"1.0.0","packpier":{"apiVersion":3}}))
        prefs.write_text(json.dumps({"packages":settings}))
        assert ids(session(folder)[0]) == builtin
        assert not pending.exists() and custom not in json.loads(prefs.read_text())["packages"]
    print("PASS uninstall, repeated request, built-in protection, preserved preferences and interrupted removal")

    from zipfile import ZipFile
    with TemporaryDirectory() as tmp:
        store = Path(tmp) / "library"
        (store / "packages").mkdir(parents=True)
        archive = Path(tmp) / "original.zip"
        manifest = {"name": "example", "version": "1.0", "packpier": {"apiVersion": 3}}
        with ZipFile(archive, "w") as z:
            z.writestr("example/package.json", json.dumps(manifest))
            z.writestr("example/README.md", "Fixture")
        exported = Path(tmp) / "export.zip"
        install = ("installLocalPackage", {"sourcePath": str(archive)})
        export = ("exportPackage", {"packageID": "example", "destinationPath": str(exported)})
        _, installed, repeated, plan, result, removed = session(
            store, install, install, ("getWindowPlan", {}), export, ("deletePackage", {"packageID": "example"}))
        assert ids(installed) == ids(repeated) == ["example"]
        assert plan["result"]["packages"] == [] and ids(result) == ["example"] and ids(removed) == []
        assert exported.read_bytes() == archive.read_bytes()
        with ZipFile(archive, "w") as z:
            z.writestr("package.json", json.dumps(dict(manifest, name="prism")))
        assert "error" in session(store, install)[1] and ids(session(store)[0]) == []
        print("PASS custom ZIP import, idempotency, original archive export, builtin protection, removal")

    with TemporaryDirectory() as tmp:
        store = Path(tmp) / "library"
        store.mkdir()
        bundles = root / "build/Packpier.app/Contents/Resources/BundledPlugins"
        for name in ["prism", "custom-background", "p-sign"]:
            path = store / "packages" / name
            path.mkdir(parents=True)
            (path / "package.json").write_text(json.dumps({"name": name, "version": "0.0.1", "packpier": {"apiVersion": 3}}))
        prefs = store / "app-state.json"
        prefs.write_text(json.dumps({"enabled": False, "disabledPackageIDs": ["prism"]}))
        baseline = {p: p.read_bytes() for p in store.rglob("*.json")}
        request = {"id": 1, "method": "initialize", "params": {
            "libraryDirectory": str(store), "bundledPackagesDirectory": str(bundles)}}
        raw = subprocess.run([binary], input=json.dumps(request) + "\n", text=True,
                             capture_output=True, timeout=8, check=True)
        state = next(msg["result"] for msg in map(json.loads, raw.stdout.splitlines()) if msg.get("id") == 1)
        for row in state["packages"]:
            version = json.loads((bundles / row["id"] / "package.json").read_bytes())["version"]
            assert row["manifest"]["version"] == row["activeBuild"]["version"] == version
        assert state["disabledPackageIDs"] == ["prism"]
        assert all(p.read_bytes() == content for p, content in baseline.items())
        print("PASS upgrade reports shipped builtin versions and preserves all existing JSON")

    with TemporaryDirectory(prefix="packpier-background-upgrade-") as tmp:
        home = Path(tmp)
        store = home / "library"
        contents = root / "build/Packpier.app/Contents"
        bundles = contents / "Resources/BundledPlugins"
        order = ["prism", "custom-background", "p-sign"]
        background = "custom-background"
        installed = store / "packages" / "renamed-background-folder"
        previous = {"name": background, "version": "1.3.18", "packpier": {"apiVersion": 3}}
        for name in order:
            path = installed if name == background else store / "packages" / name
            path.mkdir(parents=True)
            manifest = previous if name == background else json.loads((bundles / name / "package.json").read_bytes())
            (path / "package.json").write_text(json.dumps(manifest))
        (installed / "old-source.js").write_text("// 1.3.18 renderer")
        (store / "Backups").mkdir()

        disabled = [background]
        user_files = {
            store / "app-state.json": {"enabled": False, "disabledPackageIDs": disabled, "knownPackageIDs": order},
            store / "package-settings.json": {"packages": {
                name: {"priorityOverride": index * 16} for index, name in enumerate(order)
            }},
            store / "node-data/2f4e9f248cb97922/preferences-fixture.json": {"colors": {"project:test": "#4287F5"}},
            installed / "local.json": {"preserveInBackup": True},
        }
        for path, value in user_files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2))
        local = user_files.pop(installed / "local.json")
        original = {path.name: path.read_bytes() for path in installed.iterdir()}
        originals = {path: path.read_bytes() for path in user_files}
        favorite = home / "Pictures/Packpier/收藏/fixture.png"
        favorite.parent.mkdir(parents=True)
        favorite.write_bytes(b"fixture image")
        request = {"id": 1, "method": "initialize", "params": {
            "libraryDirectory": str(store), "bundledPackagesDirectory": str(bundles)}}
        for _ in range(2):
            raw = subprocess.run([contents / "Helpers/packpier-codex-loader"],
                                 input=json.dumps(request) + "\n", text=True, capture_output=True, timeout=8, check=True,
                                 env={**os.environ, "HOME": tmp, "CFFIXED_USER_HOME": tmp})
            reply = next(msg for msg in map(json.loads, raw.stdout.splitlines()) if msg.get("id") == 1)
            assert ids(reply) == order and reply["result"]["disabledPackageIDs"] == disabled
            row = next(row for row in reply["result"]["packages"] if row["id"] == background)
            assert row["manifest"]["version"] == row["activeBuild"]["version"] == "1.3.19"
            assert json.loads((installed / "package.json").read_bytes())["version"] == "1.3.19"
            assert (installed / "src/thread-clipping.js").read_bytes() == (bundles / background / "src/thread-clipping.js").read_bytes()
            backup, = (store / "Backups").iterdir()
            assert backup.name.startswith(background + "-1.3.18-")
            assert {path.name: path.read_bytes() for path in backup.iterdir()} == original
            assert json.loads((backup / "local.json").read_bytes()) == local
            assert all(path.read_bytes() == data for path, data in originals.items())
            assert favorite.read_bytes() == b"fixture image"
    print("PASS packaged loader migrates background 1.3.18 -> 1.3.19 once and preserves packages, settings and favorites")
