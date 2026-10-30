#!/bin/bash
# ==============================================================================
# build_pkg.command — 一鍵編譯並打包官方標準安裝套件 (gg.pkg)
# 支援：雙擊直接在 Finder 執行，或在終端機執行 ./build_pkg.command
# ==============================================================================
set -euo pipefail

# 切換至專案根目錄
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gg-package.XXXXXX")"
OUTPUT_PKG="${GG_PACKAGE_OUTPUT:-$PROJECT_DIR/gg.pkg}"
TEMP_PKG=""

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

cleanup() {
    if [ -x "$LSREGISTER" ]; then
        [ -d "$WORK_DIR/DerivedData/Build/Products/Release/gg.app" ] && "$LSREGISTER" -u "$WORK_DIR/DerivedData/Build/Products/Release/gg.app" 2>/dev/null || true
        [ -d "$WORK_DIR/root/Library/Input Methods/gg.app" ] && "$LSREGISTER" -u "$WORK_DIR/root/Library/Input Methods/gg.app" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    if [ -n "$TEMP_PKG" ]; then
        rm -f "$TEMP_PKG"
    fi
}
trap cleanup EXIT

echo "================================================================================"
echo "  gg 輸入法 — 一鍵編譯與打包官方標準套件 (gg.pkg)"
echo "================================================================================"

# 0. 記憶固化檢查（若帶有 --solidify 參數）
SOLIDIFY_FLAG=false
for arg in "$@"; do
    if [ "$arg" = "--solidify" ]; then
        SOLIDIFY_FLAG=true
    fi
done

if [ "$SOLIDIFY_FLAG" = true ]; then
    echo "[0/3] 正在執行日常打字記憶固化 (Tools/solidify_memory.py)..."
    python3 "$PROJECT_DIR/Tools/solidify_memory.py"
fi

# 1. 使用本次執行專屬的暫存路徑，不清理其他建置資料
BUILD_DIR="$WORK_DIR/DerivedData"

# 2. 開始 Release 最佳化編譯（使用獨立本地 derivedDataPath，不污染系統 Xcode 目錄）
echo "[1/3] 正在以 Release 最佳化模式編譯 gg 輸入法..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath "$BUILD_DIR" build -quiet

RELEASE_APP="$BUILD_DIR/Build/Products/Release/gg.app"

if [ ! -d "$RELEASE_APP" ] || [ ! -x "$RELEASE_APP/Contents/MacOS/gg" ]; then
    echo "[錯誤] 找不到 Release 編譯產物，請檢查 Xcode 編譯設定。"
    exit 1
fi

if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$RELEASE_APP" 2>/dev/null || true
fi

INFO_PLIST="$RELEASE_APP/Contents/Info.plist"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [ "$APP_BUNDLE_ID" != "com.kevin.inputmethod.gg" ]; then
    echo "[錯誤] 輸入法識別碼錯誤：$APP_BUNDLE_ID"
    exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :ComponentInputModeDict:tsInputModeListKey:com.kevin.inputmethod.gg.Bopomofo' "$INFO_PLIST" >/dev/null
if [ ! -f "$RELEASE_APP/Contents/Resources/data.txt" ]; then
    echo "[錯誤] 編譯產物缺少注音字典 data.txt。"
    exit 1
fi

# 3. 準備本次封裝專屬的暫存目錄
echo "[2/3] 準備安裝目錄結構與系統註冊腳本..."
PKG_ROOT="$WORK_DIR/root"
PKG_SCRIPTS="$PROJECT_DIR/Packaging/scripts"
mkdir -p "$PKG_ROOT/Library/Input Methods"
if [ ! -x "$PKG_SCRIPTS/postinstall" ]; then
    echo "[錯誤] 找不到可執行的 postinstall 腳本。"
    exit 1
fi

# 複製應用程式至全域輸入法目標路徑
TARGET_APP="$PKG_ROOT/Library/Input Methods/gg.app"
cp -R "$RELEASE_APP" "$TARGET_APP"

xattr -cr "$TARGET_APP"

# 簽署 Frameworks 與主應用程式
if [ -d "$TARGET_APP/Contents/Frameworks" ]; then
    find "$TARGET_APP/Contents/Frameworks" -maxdepth 2 \( -name "*.framework" -o -name "*.dylib" \) -exec codesign --force --sign - {} \;
fi
codesign --force --sign - "$TARGET_APP"

# 驗證簽章
codesign --verify --deep --strict "$TARGET_APP"

# 4. 分析並產生非重定位組件設定檔 (BundleIsRelocatable = false，防止安裝至 gg.localized)
# 同時關閉 BundleIsVersionChecked 並移除 BundleOverwriteAction，防止 PackageKit 判定降級而跳過解壓縮
COMPONENT_PLIST="$WORK_DIR/components.plist"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST"

python3 -c "
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    pl = plistlib.load(f)
for item in pl:
    item['BundleIsRelocatable'] = False
    item['BundleIsVersionChecked'] = False
    if 'BundleOverwriteAction' in item:
        del item['BundleOverwriteAction']
with open(path, 'wb') as f:
    plistlib.dump(pl, f)
" "$COMPONENT_PLIST"

# 5. 封裝官方標準 .pkg
echo "[3/3] 正在透過 macOS 原生 pkgbuild 封裝標準套件..."
mkdir -p "$(dirname "$OUTPUT_PKG")"
TEMP_PKG="$OUTPUT_PKG.tmp.$$"
rm -f "$TEMP_PKG"

VERSION=$(defaults read "$RELEASE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.4.0")

pkgbuild --root "$PKG_ROOT" \
         --component-plist "$COMPONENT_PLIST" \
         --scripts "$PKG_SCRIPTS" \
         --identifier "com.kevin.inputmethod.gg" \
         --version "$VERSION" \
         --install-location "/" \
         "$TEMP_PKG"

if [ ! -s "$TEMP_PKG" ]; then
    echo "[錯誤] pkgbuild 沒有產生有效套件。"
    exit 1
fi
PACKAGE_INSPECTION="$WORK_DIR/package-inspection"
pkgutil --expand "$TEMP_PKG" "$PACKAGE_INSPECTION"
PAYLOAD_FILE="$(find "$PACKAGE_INSPECTION" -type f -name Payload -print -quit)"
if [ -z "$PAYLOAD_FILE" ]; then
    echo "[錯誤] 套件內找不到安裝 Payload。"
    exit 1
fi
mv -f "$TEMP_PKG" "$OUTPUT_PKG"
TEMP_PKG=""

PKG_SIZE="$(du -h "$OUTPUT_PKG" | awk '{print $1}')"

echo "================================================================================"
echo "[完成] 官方標準安裝套件已打包完成！"
echo "[產物] $OUTPUT_PKG ($PKG_SIZE)"
echo "[提示] 使用者雙擊此 gg.pkg 即可由 macOS 官方安裝精靈完成安裝與自動註冊。"
echo "================================================================================"
