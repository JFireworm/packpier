#!/bin/bash
set -eu
source_icon=$1
output=$2
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
catalog="$stage/Packpier.xcassets"
mkdir -p "$catalog" "$stage/compiled"
/usr/bin/iconutil -c iconset "$source_icon" -o "$stage/AppIcon.iconset"
mv "$stage/AppIcon.iconset" "$catalog/AppIcon.appiconset"
echo '{"info":{"author":"Packpier","version":1}}' > "$catalog/Contents.json"
(
  cd "$catalog/AppIcon.appiconset"
  echo '{"images":['
  sep=''
  for size in 16 32 128 256 512; do
    for scale in 1 2; do
      suffix=''
      if [[ $scale == 2 ]]; then suffix='@2x'; fi
      file="icon_${size}x${size}${suffix}.png"
      test -f "$file"
      printf '%s{"idiom":"mac","size":"%sx%s","scale":"%sx","filename":"%s"}' "$sep" "$size" "$size" "$scale" "$file"
      sep=','
    done
  done
  echo '],"info":{"author":"Packpier","version":1}}'
) > "$catalog/AppIcon.appiconset/Contents.json"
/usr/bin/xcrun actool --compile "$stage/compiled" --platform macosx --target-device mac --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$stage/icon.plist" "$catalog"
/bin/cp "$stage/compiled/Assets.car" "$output"
