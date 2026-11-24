#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
sparkle="${SPARKLE_FRAMEWORK_PATH:-$PWD/build/Dependencies/Sparkle.framework}"
xcrun swiftc -D PACKPIER_TEST -D PACKPIER_INDEPENDENT -swift-version 5 -parse-as-library -module-cache-path build/ModuleCache -import-objc-header Sources/UpdateBridge.h -F "$(dirname "$sparkle")" -framework Sparkle -Xlinker -rpath -Xlinker "$(dirname "$sparkle")" Sources/*.swift Plugins/WeChatCeladon/Sources/WeChatCeladon/*.swift Tests/{SwiftUnit,CodexRestartCheck,MarketApplicationsCheck,WeChatOverlayCheck,NativeUI}.swift -o build/unit-tests
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
HOME="$test_home" CFFIXED_USER_HOME="$test_home" PACKPIER_TEST_APP="${PACKPIER_TEST_APP:-$PWD/build/Packpier.app}" ./build/unit-tests
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/ModuleCache Loader/NativeJSON.swift Loader/Services/*.swift Tests/NativeServices.swift -o build/native-service-tests
HOME="$test_home" CFFIXED_USER_HOME="$test_home" ./build/native-service-tests
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/ModuleCache \
    Sources/{SharedTypes,LocalPackage,BuiltInPackageIDs}.swift Loader/{PluginLibrary,SystemNode,NodeSource,NodeWorker,ThirdPartyNodes}.swift \
    Tests/SystemNodeCheck.swift -o build/system-node-tests
HOME="$test_home" CFFIXED_USER_HOME="$test_home" ./build/system-node-tests
