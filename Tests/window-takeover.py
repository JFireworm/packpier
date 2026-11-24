"""Use the production CDP client and injection pipeline on a disposable Chrome page."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.request import urlopen

root = Path(__file__).resolve().parents[1]
app = root / "build/Packpier.app"
chrome = os.environ.get("CHROME_BIN", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
with tempfile.TemporaryDirectory(prefix="packpier-takeover-") as tmp:
    work = Path(tmp)
    helper = work / "window-takeover"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", work / "modules",
                    *(root / "Loader" / f"{name}.swift" for name in ("NativeJSON", "CDPPage", "WindowInjection")),
                    root / "Tests/WindowTakeover.swift", "-o", helper], check=True)
    fixture = work / "fixture.html"
    fixture.write_text("<!doctype html><html><body></body></html>")
    profile = work / "profile"
    with subprocess.Popen([chrome, "--headless", "--disable-background-networking", "--disable-extensions",
                           "--no-first-run", "--disable-sync", "--remote-debugging-port=0",
                           "--user-data-dir=" + str(profile), fixture.as_uri()],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as browser:
        try:
            endpoint = profile / "DevToolsActivePort"
            deadline = time.monotonic() + 10
            target = None
            while time.monotonic() < deadline and browser.poll() is None:
                if endpoint.exists():
                    port = endpoint.read_text().splitlines()[0]
                    with urlopen(f"http://127.0.0.1:{port}/json/list", timeout=1) as response:
                        targets = json.load(response)
                    target = next((item for item in targets if item.get("url") == fixture.as_uri()), None)
                    if target:
                        break
                time.sleep(0.1)
            assert target, "Fixture page did not launch"
            subprocess.run([helper, target["webSocketDebuggerUrl"],
                            app / "Contents/Resources/WindowHost/window-effects.js"], check=True, timeout=45)
        finally:
            if browser.poll() is None:
                browser.terminate()
                try:
                    browser.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    browser.kill()
                    browser.wait()
