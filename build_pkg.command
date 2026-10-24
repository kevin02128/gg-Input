#!/bin/bash
# ==============================================================================
# build_pkg.command — 一鍵編譯並打包官方標準安裝套件 (gg.pkg)
# 支援：雙擊直接在 Finder 執行，或在終端機執行 ./build_pkg.command
# ==============================================================================
set -e

# 切換至專案根目錄（無論從 Finder 雙擊或終端機呼叫均能正確認識路徑）
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "================================================================================"
echo "  gg 輸入法 — 一鍵編譯與打包官方標準套件 (gg.pkg)"
echo "================================================================================"

# 1. 清理過期預編譯快取，防止因 timestamp 變動導致編譯中斷
rm -rf ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Intermediates.noindex/PrecompiledHeaders 2>/dev/null || true

# 2. 開始 Release 最佳化編譯
echo "[1/3] 正在以 Release 最佳化模式編譯 gg 輸入法..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Release -destination "platform=macOS,arch=arm64" build -quiet

RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Release -maxdepth 1 \( -name "gg.app" -o -name "McBopomofo.app" \) 2>/dev/null | head -n 1)

if [ ! -d "$RELEASE_APP" ]; then
    echo "[錯誤] 找不到 Release 編譯產物，請檢查 Xcode 編譯設定。"
    exit 1
fi

# 3. 準備打包暫存目錄
echo "[2/3] 準備安裝目錄結構與系統註冊腳本..."
BUILD_STAGE="$PROJECT_DIR/build_pkg_stage"
PKG_ROOT="$BUILD_STAGE/root"
PKG_SCRIPTS="$BUILD_STAGE/scripts"

rm -rf "$BUILD_STAGE"
mkdir -p "$PKG_ROOT/Library/Input Methods"
mkdir -p "$PKG_SCRIPTS"

# 複製應用程式至全域輸入法目標路徑
cp -R "$RELEASE_APP" "$PKG_ROOT/Library/Input Methods/gg.app"
xattr -cr "$PKG_ROOT/Library/Input Methods/gg.app"
codesign --force --deep --sign - "$PKG_ROOT/Library/Input Methods/gg.app"

# 寫入 postinstall 腳本（Apple 官方安裝器安裝完成後自動重啟進程與註冊）
cat << 'EOF' > "$PKG_SCRIPTS/postinstall"
#!/bin/bash
killall -9 gg 2>/dev/null || true
pkill -9 -f gg.app 2>/dev/null || true

# 清理各使用者家目錄下可能殘留的舊版 gg.app（避免使用者目錄版本優先於系統目錄）
find /Users -maxdepth 4 -name "gg.app" -path "*/Library/Input Methods/gg.app" -exec rm -rf {} + 2>/dev/null || true

TARGET_APP="/Library/Input Methods/gg.app"
if [ -d "$TARGET_APP" ]; then
    xattr -cr "$TARGET_APP"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$TARGET_APP" 2>/dev/null || true
fi
exit 0
EOF
chmod +x "$PKG_SCRIPTS/postinstall"

# 4. 封裝官方標準 .pkg
echo "[3/3] 正在透過 macOS 原生 pkgbuild 封裝標準套件..."
OUTPUT_PKG="$PROJECT_DIR/gg.pkg"
rm -f "$OUTPUT_PKG"

VERSION=$(defaults read "$RELEASE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

pkgbuild --root "$PKG_ROOT" \
         --scripts "$PKG_SCRIPTS" \
         --identifier "com.wtf.inputmethod.gg" \
         --version "$VERSION" \
         --install-location "/" \
         "$OUTPUT_PKG"

# 清理暫存結構與多餘 DMG
rm -rf "$BUILD_STAGE"
rm -f "$PROJECT_DIR/gg.dmg" "$PROJECT_DIR/gg.lite.dmg"

PKG_SIZE=$(ls -lh "$OUTPUT_PKG" | awk '{print $5}')

echo "================================================================================"
echo "[完成] 官方標準安裝套件已打包完成！"
echo "[產物] $OUTPUT_PKG ($PKG_SIZE)"
echo "[提示] 使用者雙擊此 gg.pkg 即可由 macOS 官方安裝精靈完成安裝與自動註冊。"
echo "================================================================================"

# 自動在 Finder 中醒目標示產出的 gg.pkg
open -R "$OUTPUT_PKG" 2>/dev/null || true
