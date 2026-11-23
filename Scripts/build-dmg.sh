#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/Packpier.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
arch="$(/usr/bin/lipo -archs "$app/Contents/MacOS/Packpier")"
image="build/Packpier-$version-macOS-$arch.dmg"
/usr/bin/codesign --verify --deep --strict "$app"
tmp="$(mktemp -d build/installer.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
uvx --from dmgbuild==1.6.7 dmgbuild --no-hidpi -s Scripts/installer.json Packpier "$tmp/Packpier.dmg"
/usr/bin/hdiutil verify -quiet "$tmp/Packpier.dmg"
mv "$tmp/Packpier.dmg" "$image"
echo "$image"
