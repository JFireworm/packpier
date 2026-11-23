#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
sparkle="${SPARKLE_FRAMEWORK_PATH:-$PWD/build/Dependencies/Sparkle.framework}"
xcrun swiftc -D PACKPIER_TEST -D PACKPIER_INDEPENDENT -swift-version 5 -parse-as-library -module-cache-path build/ModuleCache -import-objc-header Sources/UpdateBridge.h -F "$(dirname "$sparkle")" -framework Sparkle -Xlinker -rpath -Xlinker "$(dirname "$sparkle")" Sources/*.swift Plugins/WeChatCeladon/Sources/WeChatCeladon/*.swift Tests/{SwiftUnit,MarketApplicationsCheck,WeChatOverlayCheck,NativeUI}.swift -o build/unit-tests
PACKPIER_TEST_APP="$PWD/build/Packpier.app" ./build/unit-tests
