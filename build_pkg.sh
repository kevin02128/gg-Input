#!/bin/bash
# ==============================================================================
# build_pkg.sh — 製作官方標準 macOS 安裝套件 (gg.pkg)
# ==============================================================================
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "[1/4] 開始編譯 gg 輸入法 (Release 版本)..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Release -destination "platform=macOS,arch=arm64" build -quiet

RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Release -maxdepth 1 \( -name "gg.app" -o -name "McBopomofo.app" \) 2>/dev/null | head -n 1)

if [ ! -d "$RELEASE_APP" ]; then
    echo "[錯誤] 找不到 Release 編譯產物，請檢查編譯狀態。"
    exit 1
fi

echo "[2/4] 準備打包目錄結構..."
BUILD_STAGE="$PROJECT_DIR/build_pkg_stage"
PKG_ROOT="$BUILD_STAGE/root"
PKG_SCRIPTS="$BUILD_STAGE/scripts"

rm -rf "$BUILD_STAGE"
mkdir -p "$PKG_ROOT/Library/Input Methods"
mkdir -p "$PKG_SCRIPTS"

# 複製應用程式至安裝目標路徑
cp -R "$RELEASE_APP" "$PKG_ROOT/Library/Input Methods/gg.app"
xattr -cr "$PKG_ROOT/Library/Input Methods/gg.app"
codesign --force --deep --sign - "$PKG_ROOT/Library/Input Methods/gg.app"

# 寫入 postinstall 腳本（安裝完成後自動重啟與註冊）
cat << 'EOF' > "$PKG_SCRIPTS/postinstall"
#!/bin/bash
killall -9 gg 2>/dev/null || true
pkill -9 -f gg.app 2>/dev/null || true
TARGET_APP="/Library/Input Methods/gg.app"
if [ -d "$TARGET_APP" ]; then
    xattr -cr "$TARGET_APP"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$TARGET_APP" 2>/dev/null || true
fi
exit 0
EOF
chmod +x "$PKG_SCRIPTS/postinstall"

echo "[3/4] 使用 macOS 原生 pkgbuild 封裝標準安裝套件..."
OUTPUT_PKG="$PROJECT_DIR/gg.pkg"
rm -f "$OUTPUT_PKG"

VERSION=$(defaults read "$RELEASE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

pkgbuild --root "$PKG_ROOT" \
         --scripts "$PKG_SCRIPTS" \
         --identifier "com.wtf.inputmethod.gg" \
         --version "$VERSION" \
         --install-location "/" \
         "$OUTPUT_PKG"

rm -rf "$BUILD_STAGE"

echo "[4/4] 封裝完成！"
echo "[產物] $OUTPUT_PKG"
echo "[提示] 使用者雙擊此 gg.pkg 即可由 macOS 官方安裝精靈完成安裝與自動註冊。"
