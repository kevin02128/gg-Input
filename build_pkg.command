#!/bin/bash
# ==============================================================================
# build_pkg.command — 一鍵編譯並打包官方標準安裝套件 (gg.pkg)
# 支援：雙擊直接在 Finder 執行，或在終端機執行 ./build_pkg.command
# ==============================================================================
set -e

# 切換至專案根目錄
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "================================================================================"
echo "  gg 輸入法 — 一鍵編譯與打包官方標準套件 (gg.pkg)"
echo "================================================================================"

# 1. 清理過期預編譯快取
rm -rf ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Intermediates.noindex/PrecompiledHeaders ~/Library/Developer/Xcode/DerivedData/anev-*/Build/Intermediates.noindex/PrecompiledHeaders 2>/dev/null || true

# 2. 開始 Release 最佳化編譯
echo "[1/3] 正在以 Release 最佳化模式編譯 gg 輸入法..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Release -destination "platform=macOS,arch=arm64" build -quiet

RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Release -maxdepth 1 -name "gg.app" 2>/dev/null | head -n 1)

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
pkill -9 -f "gg.app" 2>/dev/null || true

# 清理各使用者家目錄下可能殘留的舊版（避免使用者目錄版本優先於系統目錄）
for USER_APP in /Users/*/Library/"Input Methods"/gg.app; do
    if [ -d "$USER_APP" ]; then
        rm -rf "$USER_APP" 2>/dev/null || true
    fi
done

TARGET_APP="/Library/Input Methods/gg.app"
if [ -d "$TARGET_APP" ]; then
    xattr -cr "$TARGET_APP"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$TARGET_APP" 2>/dev/null || true

    # 自動以目前登入之桌面使用者註冊 TIS 輸入來源並啟動最新進程
    CONSOLE_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "")
    if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
        CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")
        if [ -n "$CONSOLE_UID" ]; then
            launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" "$TARGET_APP/Contents/MacOS/gg" install --all 2>/dev/null || true
            launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" open "$TARGET_APP" 2>/dev/null || true
        else
            sudo -u "$CONSOLE_USER" "$TARGET_APP/Contents/MacOS/gg" install --all 2>/dev/null || true
            sudo -u "$CONSOLE_USER" open "$TARGET_APP" 2>/dev/null || true
        fi

        # 自動確保目前使用者之 HIToolbox 白名單已啟用 gg 輸入法
        USER_HOME=$(eval echo "~$CONSOLE_USER")
        HITOOLBOX="$USER_HOME/Library/Preferences/com.apple.HIToolbox.plist"
        if [ -f "$HITOOLBOX" ]; then
            python3 -c "
import plistlib, sys
p = sys.argv[1]
try:
    with open(p, 'rb') as f:
        d = plistlib.load(f)
    sources = d.get('AppleEnabledInputSources', [])
    sources = [s for s in sources if not (s.get('Bundle ID') == 'com.kevin.inputmethod.gg' and s.get('InputSourceKind') == 'Keyboard Input Method')]
    has_mode = any(s.get('Bundle ID') == 'com.kevin.inputmethod.gg' and s.get('Input Mode') == 'com.kevin.inputmethod.gg.Bopomofo' for s in sources)
    if not has_mode:
        sources.append({
            'Bundle ID': 'com.kevin.inputmethod.gg',
            'Input Mode': 'com.kevin.inputmethod.gg.Bopomofo',
            'InputSourceKind': 'Input Mode'
        })
    d['AppleEnabledInputSources'] = sources
    with open(p, 'wb') as f:
        plistlib.dump(d, f)
except Exception:
    pass
" "$HITOOLBOX" 2>/dev/null || true
            chown "$CONSOLE_USER" "$HITOOLBOX" 2>/dev/null || true
        fi
        if [ -n "$CONSOLE_UID" ]; then
            launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" killall -9 cfprefsd TextInputMenuAgent TextInputSwitcher CursorUIViewService 2>/dev/null || true
        fi
        killall -9 TextInputMenuAgent TextInputSwitcher CursorUIViewService 2>/dev/null || true
    fi
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
         --identifier "com.kevin.inputmethod.gg" \
         --version "$VERSION" \
         --install-location "/" \
         "$OUTPUT_PKG"

# 清理暫存結構與多餘舊檔
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$PKG_ROOT/Library/Input Methods/gg.app" 2>/dev/null || true
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
