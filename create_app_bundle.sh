#!/bin/bash

# Creates a self-contained, distributable macOS app bundle for vibedeck.
# 签名策略默认 ad-hoc，不依赖构建机上的任何私有 keychain 身份，
# 因此同一份 app 可以直接拷到另一台 Mac 上安装使用。
# 如需自己的 Developer ID 签名：VIBEDECK_SIGN_IDENTITY="Developer ID Application: ..." ./create_app_bundle.sh

set -e

APP_NAME="vibedeck"
APP_BUNDLE="${APP_NAME}.app"
APP_VERSION="1.2"
BUILD_STAMP="${VIBEDECK_BUILD_STAMP:-$(date +%Y%m%d-%H%M%S)}"

if [ ! -f "$APP_NAME" ] && [ ! -f "SiriRemote" ]; then
    echo "Error: $APP_NAME executable not found. Please build first with: ./build.sh"
    exit 1
fi
if [ -f "$APP_NAME" ]; then
    BINARY_NAME="$APP_NAME"
else
    BINARY_NAME="SiriRemote"
    echo "Note: using legacy binary name 'SiriRemote'"
fi

echo "Creating app bundle: $APP_BUNDLE"

# 避免中断的 codesign 留下 *.cstemp 导致后续签名失败
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "$BINARY_NAME" "${APP_BUNDLE}/Contents/MacOS/$APP_NAME"

# --- 图标 --------------------------------------------------------------------
ICON_SOURCE=""
for candidate in "assets/vibedeck.icns" "vibedeck.icns"; do
    if [ -f "$candidate" ]; then ICON_SOURCE="$candidate"; break; fi
done
if [ -n "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "${APP_BUNDLE}/Contents/Resources/vibedeck.icns"
    echo "Icon added: $ICON_SOURCE"
else
    echo "WARNING: vibedeck.icns not found; run: swift assets/make_icon.swift"
fi

# --- Info.plist --------------------------------------------------------------
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>dev.vibedeck.a2540</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>vibedeck</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_STAMP</string>
	<key>CFBundleShortVersionString</key>
	<string>$APP_VERSION</string>
	<key>CFBundleIconFile</key>
	<string>vibedeck</string>
	<key>NSHumanReadableCopyright</key>
	<string>vibedeck contributors</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>vibedeck 需要蓝牙权限来与 Siri Remote 的触控板通信。</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>vibedeck 需要蓝牙权限来与 Siri Remote 的触控板通信。</string>
	<key>NSInputMonitoringUsageDescription</key>
	<string>vibedeck 需要输入监控权限读取 Siri Remote 的按键事件，以便重新映射为快捷键、媒体控制或启动应用。</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>按住遥控器 Siri 键时，vibedeck 使用 Mac 麦克风录音并转成文字，插入到当前输入框。</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>vibedeck 将录下的语音转换为文字，方便直接输入到当前应用。</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>vibedeck 需要发送按键事件来实现遥控器按键到快捷键的映射。</string>
</dict>
</plist>
EOF

# 可核查的构建凭证（不写入本机路径，保证分发包不暴露构建环境）
cat > "${APP_BUNDLE}/Contents/Resources/BuildStamp.txt" <<STAMP
vibedeck v$APP_VERSION (build $BUILD_STAMP)
built at : $(date "+%Y-%m-%d %H:%M:%S %z")
bundle   : dev.vibedeck.a2540
STAMP

chmod +x "${APP_BUNDLE}/Contents/MacOS/$APP_NAME"

# --- 签名 --------------------------------------------------------------------
# 默认 ad-hoc：任何 Mac 上都能重新签名，不依赖本机 keychain。
# 新机器首次打开需按安装说明清除 quarantine，这是未公证独立应用的正常步骤。
SIGN_IDENTITY="${VIBEDECK_SIGN_IDENTITY:-}"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep -s "$SIGN_IDENTITY" "$APP_BUNDLE"
    echo "signed: $SIGN_IDENTITY"
else
    codesign --force --deep -s - "$APP_BUNDLE"
    echo "signed: ad-hoc (portable, no local keychain dependency)"
fi

codesign --verify --deep --strict "$APP_BUNDLE"
echo "✓ App bundle created: $APP_BUNDLE  (v$APP_VERSION build $BUILD_STAMP)"
echo "  $(file "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | sed 's/.*: //')"
echo ""
echo "Next: ./package_release.sh  (DMG + ZIP + 安装脚本 + 说明)"
