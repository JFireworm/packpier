"""Stage an independent Packpier plugin library in a new local directory."""
import argparse
import ctypes
from hashlib import sha256
import os
from pathlib import Path
import shutil
import stat
import tempfile


def fingerprint(path):
    with path.open("rb") as stream:
        digest = sha256()
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
        return digest.digest()


def inventory(root):
    files = {}
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"Expected a local directory: {root}")
    for entry in root.rglob("*"):
        kind = entry.lstat().st_mode
        if stat.S_ISDIR(kind) or entry.name == ".DS_Store":
            continue
        if not stat.S_ISREG(kind):
            raise ValueError(f"Inspect the non-regular file before migration: {entry}")
        files[entry.relative_to(root)] = fingerprint(entry)
    return files


def source_files(source):
    selected = {}
    for old, new in (("Tweaks/packages", "packages"), ("State/NodeData", "node-data")):
        folder = source / old
        if old.endswith("NodeData") and not folder.exists() and not folder.is_symlink():
            continue
        for name, digest in inventory(folder).items():
            selected[Path(new) / name] = (folder / name, digest)
    for name in ("app-state.json", "package-settings.json"):
        file = source / "State" / name
        if file.is_symlink():
            raise ValueError(f"Unexpected symlink: {file}")
        if file.is_file():
            selected[Path(name)] = (file, fingerprint(file))
    return selected


def migrate(source, destination):
    source = source.resolve(strict=True)
    destination = destination.absolute()
    if destination.is_symlink():
        raise ValueError("Choose a destination directory, not a symlink")
    destination = destination.resolve()
    if source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError("Source and destination must be separate directories")
    selected = source_files(source)
    expected = {name: item[1] for name, item in selected.items()}
    if destination.exists():
        existing = inventory(destination)
        existing.pop(Path(".packpier.lock"), None)
        if existing != expected:
            raise ValueError("Destination differs. Choose a new directory or keep the existing library.")
        return "Already verified", len(selected)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".packpier-import-", dir=destination.parent) as temporary:
        stage = Path(temporary) / "library"
        stage.mkdir(mode=0o700)
        (stage / "packages").mkdir(mode=0o700)
        (stage / "node-data").mkdir(mode=0o700)
        for name, (file, _) in selected.items():
            target = stage / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            shutil.copy2(file, target)
        if inventory(stage) != expected or source_files(source) != selected:
            raise ValueError("Data changed during migration. The staged copy was discarded.")
        # Never merge into an existing library, including one created by another process.
        rename_exclusively = ctypes.CDLL(None, use_errno=True).renamex_np
        rename_exclusively.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        if rename_exclusively(os.fsencode(stage), os.fsencode(destination), 4) != 0:  # Darwin RENAME_EXCL
            code = ctypes.get_errno()
            raise OSError(code, os.strerror(code), str(destination))
    return "Migrated and verified", len(selected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="previous loader's application support directory")
    parser.add_argument("destination", type=Path, help="a new private directory outside the source")
    args = parser.parse_args()
    try:
        status, count = migrate(args.source, args.destination)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"{status}: {count} files")
