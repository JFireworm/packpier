#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
export MACOSX_DEPLOYMENT_TARGET=14.0
xcrun swiftc -swift-version 5 -O -module-cache-path build/ModuleCache Sources/SharedTypes.swift Sources/LocalPackage.swift Sources/CodexListener.swift Sources/BuiltInPackageIDs.swift Loader/*.swift Loader/Services/*.swift -o build/packpier-loader
