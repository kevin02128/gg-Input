#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "正在編譯 Release 正式發行版本..."
xcodebuild -project gg.xcodeproj -scheme gg -configuration Release -destination "platform=macOS,arch=arm64" build -quiet

# 找到 Release 編譯出的輸入法模組
RELEASE_GG=$(find ~/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/Release -maxdepth 1 \( -name "gg.app" -o -name "McBopomofo.app" \) 2>/dev/null | head -n 1)

# 建置一體化 gg 控制台
"$PROJECT_DIR/build_control_center.sh"

DEST_LOCAL_APP="$PROJECT_DIR/gg 控制台.app"

# 確保控制台內嵌的是剛才編譯好的 Release 1.0.0 版本（包含 107MB KyonLM 模型）
if [ -d "$RELEASE_GG" ]; then
    rm -rf "$DEST_LOCAL_APP/Contents/Resources/gg.app"
    cp -R "$RELEASE_GG" "$DEST_LOCAL_APP/Contents/Resources/gg.app"
fi

xattr -cr "$DEST_LOCAL_APP"

# 3. 製作客戶端發布用的 DMG 磁碟映像檔
echo "正在打包客戶專用 DMG 磁碟映像檔..."
DMG_STAGE="$PROJECT_DIR/build_dmg_tmp"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

cp -R "$DEST_LOCAL_APP" "$DMG_STAGE/gg 控制台.app"
xattr -cr "$DMG_STAGE/gg 控制台.app"

# 建立 Applications 捷徑，讓使用者直覺拖曳安裝
ln -s /Applications "$DMG_STAGE/Applications"

DMG_OUTPUT="$PROJECT_DIR/gg 輸入法.dmg"
rm -f "$DMG_OUTPUT"

hdiutil create -volname "gg 輸入法" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUTPUT"
rm -rf "$DMG_STAGE"

echo ""
echo "[發布完成] 檔案已就位："
echo "   1. 專案目錄安裝檔: $PROJECT_DIR/gg 控制台.app"
echo "   2. 客戶分發 DMG 檔: $PROJECT_DIR/gg 輸入法.dmg"
echo "   3. 桌面快捷安裝檔: ~/Desktop/gg 控制台.app"
echo ""
echo "[提示] 客戶只需雙擊「gg 輸入法.dmg」，即可直接開啟「gg 控制台.app」進行安裝與設定。"
