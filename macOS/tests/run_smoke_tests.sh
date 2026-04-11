#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/tests/build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swiftc \
    -o "$BUILD_DIR/macos_smoke_tests" \
    "$PROJECT_DIR/Sources/Logger.swift" \
    "$PROJECT_DIR/Sources/Config.swift" \
    "$PROJECT_DIR/Sources/Encryption.swift" \
    "$PROJECT_DIR/Sources/SrunProtocol.swift" \
    "$PROJECT_DIR/tests/SmokeTests.swift"

"$BUILD_DIR/macos_smoke_tests"
