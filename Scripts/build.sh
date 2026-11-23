#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
app="build/Packpier.app"
if [[ "${1:-}" == "--wechat-test" ]]; then app="build/Packpier WeChat Test.app"; fi
sparkle="${SPARKLE_FRAMEWORK_PATH:-$PWD/build/Dependencies/Sparkle.framework}"
test -f "$sparkle/Sparkle" || { echo "Missing Sparkle.framework" >&2; exit 1; }
if [[ "${1:-}" == "--independent" ]]; then app="build/Packpier Independent.app"; fi
bash Scripts/build-loader.sh
npm ci --prefix Loader/Renderer --no-audit --no-fund
npm run --prefix Loader/Renderer build
npm run --prefix Loader/Renderer build:host
loader="$PWD/build/packpier-loader"
mkdir -p "$app/Contents/Helpers" "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks" build/ModuleCache
export MACOSX_DEPLOYMENT_TARGET=14.0
xcrun swiftc -D PACKPIER_INDEPENDENT -swift-version 5 -O -parse-as-library -module-cache-path build/ModuleCache -import-objc-header Sources/UpdateBridge.h -F "$(dirname "$sparkle")" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/*.swift Plugins/WeChatCeladon/Sources/WeChatCeladon/*.swift -o "$app/Contents/MacOS/Packpier"
/usr/bin/ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
/usr/bin/ditto "$loader" "$app/Contents/Helpers/packpier-codex-loader"
# ditto merges directories; discard stale built-in sources and catalog ZIPs on incremental builds.
rm -rf "$app/Contents/Resources/BundledPlugins" "$app/Contents/Resources/Marketplace"
/usr/bin/ditto Resources "$app/Contents/Resources"
/bin/bash Scripts/build-app-icon.sh Resources/Packpier.icns "$app/Contents/Resources/Assets.car"
bundled="$app/Contents/Resources/BundledPlugins"
for builtin in prism custom-background; do
    dest="$bundled/$builtin"
    rm -rf "$dest"
    if [[ "$builtin" == "custom-background" ]]; then dest="$bundled"; fi
    /usr/bin/unzip -oq "Resources/Marketplace/$builtin.zip" -d "$dest"
    test -f "$bundled/$builtin/package.json"
done
/usr/bin/ditto build/Renderer/window-effects.mjs "$app/Contents/Resources/window-effects.mjs"
rm -rf "$app/Contents/Resources/WindowHost"
mkdir -p "$app/Contents/Resources/WindowHost"
/usr/bin/ditto build/Renderer/window-effects.iife.js "$app/Contents/Resources/WindowHost/window-effects.js"
/usr/bin/ditto Loader/WindowHost/window-host.mjs "$app/Contents/Resources/WindowHost/window-host.mjs"
/usr/bin/ditto Loader/WindowHost/policy.mjs "$app/Contents/Resources/WindowHost/policy.mjs"
cp Info.plist "$app/Contents/Info.plist"
if [[ "${1:-}" == "--wechat-test" ]]; then
    /usr/bin/plutil -replace CFBundleIdentifier -string local.packpier.wechat-test "$app/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleDisplayName -string "Packpier WeChat Test" "$app/Contents/Info.plist"
    /usr/bin/plutil -insert PackpierWeChatTestMode -bool YES "$app/Contents/Info.plist"
fi
if [[ -n "${PACKPIER_FEED_URL:-}${PACKPIER_PUBLIC_ED_KEY:-}" ]]; then
    : "${PACKPIER_PUBLIC_ED_KEY:?required with update feed}" "${PACKPIER_FEED_URL:?required with public key}"
    /usr/bin/plutil -replace SUFeedURL -string "$PACKPIER_FEED_URL" "$app/Contents/Info.plist"
    /usr/bin/plutil -replace SUPublicEDKey -string "$PACKPIER_PUBLIC_ED_KEY" "$app/Contents/Info.plist"
fi
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/cmp "$loader" "$app/Contents/Helpers/packpier-codex-loader"
/usr/bin/shasum -a 256 "$app/Contents/Helpers/packpier-codex-loader"
