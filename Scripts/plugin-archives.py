"""Build or check the source ZIPs used by the marketplace and application bundle."""
import argparse
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = {"prism": "Plugins/Prism", "custom-background": "Plugins/CustomBackground",
           "p-sign": "Resources/BundledPlugins/p-sign"}


def entries(plugin, directory):
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part in {".git", "node_modules", ".DS_Store", "__pycache__"} for part in relative.parts):
            continue
        if path.is_file():
            name = str(relative) if plugin != "custom-background" else f"{plugin}/{relative}"
            yield name, path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for plugin, directory in PLUGINS.items():
        files = dict(entries(plugin, ROOT / directory))
        dest = ROOT / "Resources/Marketplace" / f"{plugin}.zip"
        if args.check:
            with ZipFile(dest) as archive:
                if sorted(archive.namelist()) != sorted(files) or any(
                    archive.read(name) != path.read_bytes() for name, path in files.items()
                ):
                    raise SystemExit(f"{plugin}: source and ZIP differ")
        else:
            with TemporaryDirectory(dir=dest.parent) as tmp:
                staged = Path(tmp) / dest.name
                with ZipFile(staged, "w") as archive:
                    for name, path in files.items():
                        info = ZipInfo(name)
                        info.external_attr = 0o100644 << 16
                        archive.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED)
                staged.replace(dest)


if __name__ == "__main__":
    main()
