"""Run the bundled first-party effects against a local DOM fixture, without a user browser profile."""
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import json
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
renderer = root / "Loader/Renderer"
chrome = os.environ.get("CHROME_BIN", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
with TemporaryDirectory(prefix="packpier-effects-") as folder:
    page = Path(folder) / "check.html"
    subprocess.run(["npm", "run", "build"], cwd=renderer, check=True)
    subprocess.run([renderer / "node_modules/.bin/esbuild", root / "Tests/window-effects.js",
                    "--bundle", "--outfile=" + str(page.with_suffix(".js"))], check=True)
    # Generate the browser input through the Swift loader using real builtin manifests.
    store = Path(folder) / "library"
    for name, source in [("p-sign", "Resources/BundledPlugins/p-sign"), ("prism", "Plugins/Prism"),
                         ("custom-background", "Plugins/CustomBackground"), ("packpier-ready-badge", None)]:
        target = store / "packages" / name
        target.mkdir(parents=True)
        if source:
            shutil.copyfile(root / source / "package.json", target / "package.json")
        else:
            (target / "package.json").write_text(json.dumps({
                "name": name, "version": "1.0.0", "packpier": {"apiVersion": 3}}))
    order = ["p-sign", "prism", "packpier-ready-badge", "custom-background"]
    (store / "app-state.json").write_text(json.dumps({"enabled": True, "disabledPackageIDs": [order[2]]}))
    requests = [("initialize", {"libraryDirectory": str(store)}), ("setPackageOrder", {"packageIDs": order}),
                ("getWindowPlan", {}), ("setPackageEnabled", {"packageID": order[2], "enabled": True}),
                ("getWindowPlan", {}), ("setPackageEnabled", {"packageID": order[2], "enabled": False}),
                ("getWindowPlan", {})]
    result = subprocess.run([root / "build/packpier-loader"], input="".join(
        json.dumps({"id": i, "method": method, "params": params}) + "\n"
        for i, (method, params) in enumerate(requests)), capture_output=True, text=True, check=True)
    replies = [reply["result"] for reply in map(json.loads, result.stdout.splitlines()) if "id" in reply]
    state = replies[-1]
    expected = {"enabled": True, "packages": [{"id": name} for name in order if name != order[2]]}
    assert replies[2] == replies[4] == state == expected
    assert replies[-2]["disabledPackageIDs"] == [order[2]]
    assert [plugin["id"] for plugin in replies[-2]["packages"]] == order
    (Path(folder) / "state.js").write_text("window.fixtureState = " + json.dumps(state))
    page.write_text("""<!doctype html><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src data: blob:">
<body><script src="state.js"></script><script src="check.js"></script></body>""")
    output = subprocess.run([chrome, "--headless", "--disable-background-networking",
                             "--disable-extensions", "--no-first-run", "--disable-sync",
                             "--user-data-dir=" + str(Path(folder) / "profile"),
                             "--virtual-time-budget=3000", "--dump-dom", page.as_uri()],
                            capture_output=True, text=True, check=True, timeout=30)
    if "<body>PACKPIER_EFFECTS_PASS</body>" not in output.stdout:
        raise SystemExit(output.stdout[-1500:] or output.stderr[-1500:])
    print("PASS row color, wallpaper, P-Sign hover, image request, settings, favorites, pause and resume")
