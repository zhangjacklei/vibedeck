#!/bin/bash

# Build script for vibedeck
# 用法：
#   ./build.sh                # 只构建当前机器架构（开发用，快）
#   ./build.sh universal      # 构建 arm64 + x86_64 通用二进制（分发用）
#
# Make sure Xcode Command Line Tools are installed: xcode-select --install

set -e

echo "Building vibedeck..."

SWIFT_FILES=(
    "main.swift"
    "SiriRemoteApp.swift"
    "MenuBarManager.swift"
    "RemoteDetector.swift"
    "RemoteInputHandler.swift"
    "CursorController.swift"
    "MediaController.swift"
    "MediaKeyInterceptor.swift"
    "TouchHandler.swift"
    "PermissionPrimer.swift"
    "PermissionCenter.swift"
    "Binding.swift"
    "KeySender.swift"
    "VoiceInput.swift"
    "RemoteView.swift"
    "SettingsWindow.swift"
    "Pages.swift"
    "VoiceHUD.swift"
    "AppCatalog.swift"
    "AppPickerView.swift"
    "SelfTest.swift"
    "BuildInfo.swift"
    "ShortcutRecorder.swift"
    "PowerManager.swift"
)

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")
if [ -z "$SDK_PATH" ]; then
    echo "Error: macOS SDK not found. Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi
echo "Using SDK: $SDK_PATH"

COMMON_FLAGS=(
    -import-objc-header SiriRemote-Bridging-Header.h
    -F /System/Library/PrivateFrameworks
    -framework IOKit
    -framework CoreGraphics
    -framework AudioToolbox
    -framework Carbon
    -framework AppKit
    -framework AVFoundation
    -framework Speech
    -framework IOBluetooth
    -framework MultitouchSupport
)

build_one() {
    local target="$1"
    local output="$2"
    echo "  compiling $target -> $output"
    swiftc -sdk "$SDK_PATH" -target "$target" -o "$output" \
        "${SWIFT_FILES[@]}" "${COMMON_FLAGS[@]}"
}

MODE="${1:-native}"
HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" = "arm64" ]; then
    HOST_TARGET="arm64-apple-macosx12.0"
    OTHER_TARGET="x86_64-apple-macosx12.0"
else
    HOST_TARGET="x86_64-apple-macosx12.0"
    OTHER_TARGET="arm64-apple-macosx12.0"
fi

if [ "$MODE" = "universal" ]; then
    echo "Building universal binary (arm64 + x86_64)..."
    TMP_A="vibedeck.tmp-${HOST_TARGET%%-*}.$$"
    TMP_B="vibedeck.tmp-${OTHER_TARGET%%-*}.$$"
    trap 'rm -f "$TMP_A" "$TMP_B"' EXIT
    build_one "$HOST_TARGET" "$TMP_A"
    build_one "$OTHER_TARGET" "$TMP_B"
    lipo -create -o vibedeck "$TMP_A" "$TMP_B"
    rm -f "$TMP_A" "$TMP_B"
    trap - EXIT
    echo "Universal binary:" && lipo -info vibedeck
else
    echo "Building for: $HOST_TARGET"
    build_one "$HOST_TARGET" vibedeck
fi

echo ""
echo "✓ Build successful!  ($(file vibedeck | sed 's/.*: //'))"
echo ""
echo "To create a proper macOS app bundle, run:"
echo "  ./create_app_bundle.sh"
echo ""
echo "To build a distributable universal package, run:"
echo "  ./package_release.sh"
echo ""
