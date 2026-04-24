#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/tests/build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

SDK_PATH=$(xcrun --show-sdk-path)

swiftc \
    -o "$BUILD_DIR/macos_ui_smoke_tests" \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx11.0 \
    -framework Cocoa \
    -framework UserNotifications \
    -framework Network \
    "$PROJECT_DIR/Sources/AppRuntime.swift" \
    "$PROJECT_DIR/Sources/Logger.swift" \
    "$PROJECT_DIR/Sources/Config.swift" \
    "$PROJECT_DIR/Sources/Encryption.swift" \
    "$PROJECT_DIR/Sources/SrunProtocol.swift" \
    "$PROJECT_DIR/Sources/DirectHTTPClient.swift" \
    "$PROJECT_DIR/Sources/SrunAPI.swift" \
    "$PROJECT_DIR/Sources/UpdateChecker.swift" \
    "$PROJECT_DIR/Sources/UpdateWindow.swift" \
    "$PROJECT_DIR/Sources/SettingsWindow.swift" \
    "$PROJECT_DIR/Sources/AboutWindow.swift" \
    "$PROJECT_DIR/Sources/LaunchManager.swift" \
    "$PROJECT_DIR/Sources/StatusBarController.swift" \
    "$PROJECT_DIR/tests/UISmokeTests.swift"

"$BUILD_DIR/macos_ui_smoke_tests" --ui-smoke-test
