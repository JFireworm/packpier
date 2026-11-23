"""Build a GitHub release with Sparkle and verify the ZIP with the public key embedded in the app."""
import os
from pathlib import Path
import plistlib
import subprocess
from tempfile import TemporaryDirectory
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
REPO = "https://github.com/JFireworm/packpier"


def main():
    app = ROOT / "build/Packpier.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    if info["SUFeedURL"] != REPO + "/releases/latest/download/appcast.xml":
        raise SystemExit("Unexpected release feed")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], check=True)
    prefix = f"{REPO}/releases/download/v{version}/"
    account = os.environ.get("PACKPIER_SIGNING_ACCOUNT", "Packpier")
    with TemporaryDirectory(dir=ROOT / "build") as tmp:
        archive = Path(tmp) / f"Packpier-{version}-macOS.zip"
        xml = Path(tmp) / "appcast.xml"
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, archive], check=True)
        subprocess.run([ROOT / "build/Dependencies/bin/generate_appcast", "--account", account,
                        "--download-url-prefix", prefix, "--maximum-deltas", "0", "-o", xml, tmp], check=True)
        item = ET.parse(xml).find("./channel/item")
        if item is None or item.findtext(SPARKLE + "version") != info["CFBundleVersion"]:
            raise SystemExit("Generated feed missing the current build")
        enclosure = item.find("enclosure")
        if enclosure is None or enclosure.get("url") != prefix + archive.name or int(enclosure.get("length", "0")) != archive.stat().st_size:
            raise SystemExit("Generated feed does not match the release archive")
        subprocess.run(["xcrun", "swift", ROOT / "Scripts/verify-update.swift", info["SUPublicEDKey"],
                        enclosure.attrib[SPARKLE + "edSignature"], archive], check=True)
        for artifact in (archive, xml):
            artifact.replace(ROOT / "build" / artifact.name)
            print(ROOT / "build" / artifact.name)


if __name__ == "__main__":
    main()
