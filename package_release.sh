#!/bin/bash
# 生成可分发、脱离当前 Mac 环境的 vibedeck 安装包（DMG + ZIP）。
# 产物：dist/vibedeck.app、dist/install.command、dist/README-install.txt、
#       dist/vibedeck-macOS-universal.dmg、dist/vibedeck-macOS-universal.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "=========================================="
echo " vibedeck 可分发安装包构建"
echo "=========================================="

# 1. 图标（若缺失则现场生成）
if [ ! -f assets/vibedeck.icns ]; then
    echo "[1/6] 生成应用图标..."
    swift assets/make_icon.swift >/dev/null
    rm -rf assets/vibedeck.iconset && mkdir -p assets/vibedeck.iconset
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
                "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
        sz=${spec%%:*}; name=${spec##*:}
        sips -z "$sz" "$sz" assets/icon_base.png --out "assets/vibedeck.iconset/${name}.png" >/dev/null
    done
    iconutil -c icns assets/vibedeck.iconset -o assets/vibedeck.icns
fi

# 2. Universal 二进制 + app bundle
echo "[2/6] 构建 Universal 二进制..."
./build.sh universal

echo "[3/6] 打包自包含 app..."
./create_app_bundle.sh

# 4. 分发目录
rm -rf dist
mkdir -p dist
cp -R vibedeck.app dist/vibedeck.app

cat > dist/install.command <<'INSTALL'
#!/bin/bash
# vibedeck 一键安装：清 quarantine → 复制到 /Applications → 启动
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/vibedeck.app"
DEST="/Applications/vibedeck.app"

echo "=========================================="
echo " vibedeck 安装"
echo "=========================================="

if [ ! -d "$SRC" ]; then
  echo "错误：未找到 $SRC"
  exit 1
fi

# 未公证应用的 quarantine 属性会导致 macOS 拒绝打开，这里直接清除
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

if [ -d "$DEST" ]; then
  BACKUP="/Applications/vibedeck.app.backup.$(date +%Y%m%d-%H%M%S)"
  echo "检测到旧版本，备份到: $BACKUP"
  rm -rf "$BACKUP"
  mv "$DEST" "$BACKUP"
fi

cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "已安装到 $DEST"
echo ""
echo "首次启动后请按提示授权：辅助功能、输入监控、麦克风、语音识别。"
echo "授权路径：系统设置 → 隐私与安全性"
echo ""
open "$DEST"
INSTALL
chmod +x dist/install.command

cat > dist/README-install.txt <<'README'
vibedeck — Apple TV Siri Remote (A2540) 的 Mac 控制台
======================================================

【系统要求】
- macOS 12.0 或更新版本
- Apple Silicon (M1/M2/M3...) 或 Intel Mac 均可（Universal 二进制）
- Apple TV Siri Remote A2540（2 代，Product ID 0x0314）或其他支持的遥控器

【安装（开箱即用）】
1. 双击 DMG，把 vibedeck.app、install.command、本说明拖到任意文件夹。
2. 双击「install.command」。它会自动：
   - 清除 macOS 下载隔离属性（未公证独立应用的必要步骤）
   - 把 vibedeck.app 复制到 /Applications
   - 备份已有旧版本（vibedeck.app.backup.时间戳）
   - 启动应用
3. 如果双击 .command 被系统拦截：打开「终端」，把文件拖进终端窗口后回车。

【也可以手动安装】
- 把 vibedeck.app 拖到 /Applications
- 在终端执行：xattr -dr com.apple.quarantine /Applications/vibedeck.app
- 双击打开

【首次授权（新 Mac 上必须做一次）】
应用启动后菜单栏出现遥控器图标，窗口可能在后台，点菜单栏图标 →「打开设置面板…」。
到 系统设置 → 隐私与安全性，为 vibedeck 打开：
- 辅助功能：移动指针、注入按键、粘贴语音文字
- 输入监控：读取遥控器 HID 按键与触摸事件
- 麦克风：按住 Siri 键时录音
- 语音识别：把语音转成文字

如果概览页显示「未确认」但按键实际可用：TCC 按负责进程判定，
点概览页「重新检测」，或把对应开关关→开一次刷新。

【菜单栏功能】
- 打开设置面板 / 打开权限设置
- 暂停接管（省电）/ 恢复接管
- 睡前一键释放（释放 HID 独占与触控板轮询，遥控器会自行深睡）
- 立即测试休眠（当场验证释放/恢复链路）
- 闲置自动休眠时长（1/3/5/10/15/30/60 分钟）
- 连接状态、按键映射摘要、退出

【设置面板功能】
- 概览：连接状态、权限状态、蓝牙可见性、当前按键映射、一键重新检测
- 按键映射：13 个热区、任意按键/组合录制、多组连续动作、打开系统应用、语音输入
- 语音输入：Mac/外接麦克风选择、语言、自动粘贴、实时转写浮窗、授权状态细分
- 省电与休眠：暂停/恢复、睡前释放、闲置时长、状态一致性
- 关于：版本与构建号、上游许可说明

【已知平台限制】
- A2540 麦克风不是标准蓝牙麦克风，macOS 不向第三方 App 暴露；
  应用自动回退到 Mac 麦克风，遥控器只负责触发。
- A2540 是 BLE HID，macOS 不允许第三方 App 精确断开系统级蓝牙连接；
  「睡前一键释放」释放的是本应用的 HID 独占与触控板轮询，
  彻底断开需在系统蓝牙设置里手动操作。

【命令行自检（可选）】
/Applications/vibedeck.app/Contents/MacOS/vibedeck --selftest
/Applications/vibedeck.app/Contents/MacOS/vibedeck --diag
/Applications/vibedeck.app/Contents/MacOS/vibedeck --power-test

【卸载】
退出菜单栏图标 → Quit，然后删除 /Applications/vibedeck.app。
偏好设置位于 ~/Library/Preferences/dev.vibedeck.a2540.plist。
README

# 5. 归档
echo "[4/6] 生成 ZIP... (app + 安装脚本 + 说明)"
(cd dist && zip -q -r -y vibedeck-macOS-universal.zip vibedeck.app install.command README-install.txt)

echo "[5/6] 生成 DMG... (需要挂载临时卷；ZIP 同样可用)"
if [ "${VIBEDECK_SKIP_DMG:-0}" = "1" ]; then
    echo "DMG: 已跳过（VIBEDECK_SKIP_DMG=1）"
elif hdiutil create -volname "vibedeck" -srcfolder dist \
    -ov -format UDZO "dist/vibedeck-macOS-universal.dmg" >/dev/null 2>&1; then
    echo "DMG: OK"
else
    echo "警告：DMG 生成失败（当前环境可能禁止挂载 /Volumes），已交付 ZIP 与独立 app。"
    rm -f "dist/vibedeck-macOS-universal.dmg"
fi

echo "[6/6] 校验..."
lipo -info dist/vibedeck.app/Contents/MacOS/vibedeck
codesign --verify --deep --strict dist/vibedeck.app && echo "codesign: OK"
shasum -a 256 dist/vibedeck-macOS-universal.zip
ls -lh dist/vibedeck.app dist/vibedeck-macOS-universal.zip
if [ -f dist/vibedeck-macOS-universal.dmg ]; then ls -lh dist/vibedeck-macOS-universal.dmg; fi

echo ""
if [ -f dist/vibedeck-macOS-universal.dmg ]; then
    echo "✓ 完成：dist/vibedeck-macOS-universal.dmg 与 .zip"
else
    echo "✓ 完成：dist/vibedeck.app 与 dist/vibedeck-macOS-universal.zip"
fi
