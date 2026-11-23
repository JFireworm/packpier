"""Check shipped resources, supported actions, and update configuration before packaging."""
import base64
import json
from pathlib import Path
import plistlib
import re
from urllib.parse import unquote

root = Path(__file__).resolve().parents[1]
repo = "https://github.com/JFireworm/packpier"
catalog = json.loads((root / "Resources/Marketplace/catalog.json").read_text())
assert len({entry["id"] for entry in catalog}) == len(catalog)
for entry in catalog:
    link = entry["source"]
    assert link.startswith(repo + "/tree/main/"), link
    source = root / unquote(link.split("/tree/main/", 1)[1])
    assert source.is_dir(), source
    if entry["app"] == "codex":
        manifest = json.loads((source / "package.json").read_text())
        assert (manifest["name"], manifest["version"], manifest["homepage"]) == (
            entry["id"], entry["version"], link
        )
    assert set(entry["name"]) == set(entry["summary"]) == {"en", "ja", "ko", "zh-Hans"}
skill = (root / "Resources/Skills/packpier-plugin-author/SKILL.md").read_text()
assert "tweaks" not in skill.lower() and repo in skill
assert all(url.rstrip(").") == repo or url.startswith(repo + "/")
           for url in re.findall(r"https://github.com/[^\s)]+", skill))
info = plistlib.loads((root / "Info.plist").read_bytes())
assert info["SUFeedURL"] == repo + "/releases/latest/download/appcast.xml"
assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32
# UI commands gated on individual package capabilities are never advertised by this runtime.
loader = (root / "Loader/main.swift").read_text()
cases = set(re.findall(r'"(\w+)"', "\n".join(re.findall(r'^    case (.*?):', loader, re.M))))
manager = "\n".join(p.read_text() for p in (root / "Sources").glob("*.swift"))
calls = set(re.findall(r'(?:send|rpc)\("(\w+)"', manager))
assert not calls - cases - {"buildPackage", "authorizeNodePackage"}, calls - cases
print("PASS project links, Skill, signed update feed, marketplace metadata and loader command contract")

versions = [re.search(r'const VERSION = "([^"]+)"', (root / source).read_text()).group(1)
            for source in ("Loader/Renderer/host.js", "Loader/WindowHost/window-host.mjs")]
assert versions[0] == versions[1], "Host and renderer protocol versions differ"
