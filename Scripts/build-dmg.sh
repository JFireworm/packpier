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
xcrun swift -module-cache-path build/ModuleCache Scripts/installer-background.swift "$tmp"
/usr/bin/tiffutil -cathidpicheck "$tmp/paper-1x.tiff" "$tmp/paper-2x.tiff" -out "$tmp/paper.tiff"
mv "$tmp/paper.tiff" build/installer-paper.tiff
uvx --from dmgbuild==1.6.7 dmgbuild --no-hidpi -s Scripts/installer.json Packpier "$tmp/Packpier.dmg"
/usr/bin/hdiutil verify -quiet "$tmp/Packpier.dmg"
mv "$tmp/Packpier.dmg" "$image"
echo "$image"
