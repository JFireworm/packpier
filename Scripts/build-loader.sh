#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
source Scripts/build-target.sh
mkdir -p "$out/ModuleCache"
xcrun swiftc -target "$swift_target" -swift-version 5 -O -module-cache-path "$out/ModuleCache" Sources/SharedTypes.swift Sources/LocalPackage.swift Sources/CodexListener.swift Sources/LoaderConflict.swift Sources/BuiltInPackageIDs.swift Loader/*.swift Loader/Services/*.swift -o "$out/packpier-loader"
if [[ "$arch" == x86_64 ]]; then /usr/bin/codesign --force --sign - "$out/packpier-loader"; fi
