#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-target.sh
app="$out/Packpier.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
for binary in "$app/Contents/MacOS/Packpier" "$app/Contents/Helpers/packpier-codex-loader"; do
    [[ "$(/usr/bin/lipo -archs "$binary")" == "$arch" ]] || { echo "Expected $arch: $binary" >&2; exit 1; }
done
image="build/Packpier-$version-macOS-$arch.dmg"
/usr/bin/codesign --verify --deep --strict "$app"
tmp="$(mktemp -d "$out/installer.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun swift -module-cache-path "$out/ModuleCache" Scripts/installer-background.swift "$tmp"
/usr/bin/tiffutil -cathidpicheck "$tmp/paper-1x.tiff" "$tmp/paper-2x.tiff" -out "$tmp/paper.tiff"
mv "$tmp/paper.tiff" "$out/installer-paper.tiff"
settings="$tmp/settings.json"
cp Scripts/installer.json "$settings"
/usr/bin/plutil -replace background -string "$PWD/$out/installer-paper.tiff" "$settings"
/usr/bin/plutil -replace contents.0.path -string "$PWD/$app" "$settings"
/usr/bin/plutil -convert json "$settings"
uvx --from dmgbuild==1.6.7 dmgbuild --no-hidpi -s "$settings" Packpier "$tmp/Packpier.dmg"
/usr/bin/hdiutil verify -quiet "$tmp/Packpier.dmg"
mv "$tmp/Packpier.dmg" "$image"
echo "$image"
