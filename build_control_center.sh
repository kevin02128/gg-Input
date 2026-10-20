#!/bin/bash
# ==============================================================================
# build_control_center.sh — 建置「gg 控制台.app」一體化主控應用程式
# 具備：安裝、升級、即時狀態監控、Mode B 網路詞庫 OTA 更新、偏好設定、完全解除安裝
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "[1/4] 開始建置「gg 控制台.app」一體化主控應用程式..."

SRC_DIR="$PROJECT_DIR/Source/ControlCenter"
OUTPUT_APP="$PROJECT_DIR/gg 控制台.app"

# 1. 準備應用程式目錄結構
rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

# 2. 複製 Info.plist 與 AppIcon.icns
sed -e 's/\${EXECUTABLE_NAME}/ggControlCenter/g' -e 's/\${PRODUCT_NAME}/gg 控制台/g' "$SRC_DIR/Info.plist" > "$OUTPUT_APP/Contents/Info.plist"

ICON_SRC="$SRC_DIR/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
fi

# 內嵌一份已編譯之 gg.app 核心以支援離線安裝
BUILD_GG=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Debug/gg.app -maxdepth 0 2>/dev/null | head -n 1)
INSTALLED_GG="$HOME/Library/Input Methods/gg.app"

if [ -d "$BUILD_GG" ]; then
    cp -R "$BUILD_GG" "$OUTPUT_APP/Contents/Resources/gg.app"
elif [ -d "$INSTALLED_GG" ]; then
    cp -R "$INSTALLED_GG" "$OUTPUT_APP/Contents/Resources/gg.app"
fi

# 3. 編譯 Swift 原始檔 (SwiftUI + AppKit + Carbon)
echo "[2/4] 編譯 SwiftUI 核心程式碼..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

swiftc -O -parse-as-library \
    -target arm64-apple-macos13.0 \
    -sdk "$SDK_PATH" \
    -framework Carbon \
    "$SRC_DIR/LicenseText.swift" \
    "$SRC_DIR/ControlCenterManager.swift" \
    "$SRC_DIR/ControlCenterView.swift" \
    "$SRC_DIR/ControlCenterApp.swift" \
    -o "$OUTPUT_APP/Contents/MacOS/ggControlCenter"

chmod +x "$OUTPUT_APP/Contents/MacOS/ggControlCenter"

# 4. 進行深度代碼簽名 (解除 Apple Silicon 內核封鎖)
echo "[3/4] 套用 ARM64 本地深度代碼簽名..."
xattr -cr "$OUTPUT_APP"
codesign --force --deep --sign - "$OUTPUT_APP"
touch "$OUTPUT_APP"

# 5. 向 macOS LaunchServices 註冊為受信任應用
echo "[4/4] 向系統登記信任應用程式..."
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$OUTPUT_APP"

echo ""
echo "=============================================================================="
echo "[建置成功] 「gg 控制台.app」一體化主控應用程式已成功生成！"
echo "產物位置：$OUTPUT_APP"
echo "具備完整功能：安裝導引、升級修復、即時狀態、詞庫熱更新、設定調整、一鍵反安裝"
echo "=============================================================================="
