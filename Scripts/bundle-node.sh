#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Expected path to the built app}"
version=22.23.4
case "$(uname -m)" in
    arm64) arch=arm64; sha=c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428 ;;
    x86_64) arch=x64; sha=efcc2b0db6f94bf53eddb038fe2b370277a042bd29e4f19b8f8e23598795b819 ;;
    *) echo "Unsupported build architecture" >&2; exit 1 ;;
esac
name="node-v$version-darwin-$arch"
cache="build/Dependencies"
archive="$cache/$name.tar.gz"
mkdir -p "$cache" "$app/Contents/Helpers" "$app/Contents/Resources/Licenses"
tmp="$(mktemp -d "$cache/node.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
verify() { printf '%s  %s\n' "$sha" "$1" | /usr/bin/shasum -a 256 --check --status; }
if ! [[ -f "$archive" ]] || ! verify "$archive"; then
    /usr/bin/curl --fail --location --silent --show-error --retry 2 --max-time 110 \
        "https://nodejs.org/dist/v$version/$name.tar.gz" -o "$tmp/download"
    verify "$tmp/download"
    mv "$tmp/download" "$archive"
fi
/usr/bin/tar -xzf "$archive" -C "$tmp" "$name/bin/node" "$name/LICENSE"
/usr/bin/install -m 755 "$tmp/$name/bin/node" "$app/Contents/Helpers/node"
/usr/libexec/PlistBuddy -c "Add :PackpierNodeVersion string $version" "$app/Contents/Info.plist"
/usr/bin/install -m 644 "$tmp/$name/LICENSE" "$app/Contents/Resources/Licenses/Node.txt"
env -u NODE_OPTIONS "$app/Contents/Helpers/node" --disable-warning=ExperimentalWarning -e \
    "const db=new (require('node:sqlite').DatabaseSync)(':memory:'); if (db.prepare('select 1 as x').get().x !== 1) process.exit(1); db.close()"
