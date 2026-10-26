#!/bin/bash
# ==============================================================================
# dev_reload.sh — 開發者專用：秒級快速熱更新（免手動打開安裝程式）
# 用途：修改程式碼後，終端機執行 `./dev_reload.sh` 即可在 3 秒內自動編譯並載入最新輸入法
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "正在快速編譯 gg 輸入法..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Debug -destination "platform=macOS" build -quiet

BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Debug -maxdepth 1 -name "gg.app" 2>/dev/null | head -n 1)

if [ ! -d "$BUILD_APP" ]; then
    echo "[錯誤] 找不到編譯產物，請確認專案狀態。"
    exit 1
fi

echo "正在終止舊程序並替換輸入法模組..."
pkill -9 -f "Input Methods/gg.app" 2>/dev/null || true
pkill -9 -f "Contents/MacOS/gg" 2>/dev/null || true

# 註銷 DerivedData 編譯產物與歷史舊註冊，避免系統設定出現重複的輸入法項目
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$BUILD_APP" 2>/dev/null || true
if [ -d "/Library/Input Methods/gg.app" ]; then
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "/Library/Input Methods/gg.app" 2>/dev/null || true
fi

DEST_APP="$HOME/Library/Input Methods/gg.app"
rm -rf "$DEST_APP"
cp -R "$BUILD_APP" "$DEST_APP"
xattr -cr "$DEST_APP"
touch "$DEST_APP"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$DEST_APP"

open "$DEST_APP"

echo "[完成] gg 輸入法已自動更新並重新啟動！"
echo "[提示] 您現在可以直接在選單列或打字測試最新效果，完全不需手動跑安裝流程。"
