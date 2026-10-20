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
echo "正在打包【輕量版】DMG（無內嵌神經模型，約 9MB）..."
DMG_STAGE_LITE="$PROJECT_DIR/build_dmg_lite"
rm -rf "$DMG_STAGE_LITE"
mkdir -p "$DMG_STAGE_LITE"

cp -R "$DEST_LOCAL_APP" "$DMG_STAGE_LITE/gg 控制台.app"
xattr -cr "$DMG_STAGE_LITE/gg 控制台.app"
ln -s /Applications "$DMG_STAGE_LITE/Applications"

DMG_OUTPUT_LITE="$PROJECT_DIR/gg 輸入法 (輕量版).dmg"
rm -f "$DMG_OUTPUT_LITE"
hdiutil create -volname "gg 輸入法 (輕量版)" -srcfolder "$DMG_STAGE_LITE" -ov -format UDZO "$DMG_OUTPUT_LITE"
rm -rf "$DMG_STAGE_LITE"

echo "正在打包【完整版】DMG（內嵌 KyonLM 107MB 神經模型，約 110MB）..."
DMG_STAGE_FULL="$PROJECT_DIR/build_dmg_full"
rm -rf "$DMG_STAGE_FULL"
mkdir -p "$DMG_STAGE_FULL"

cp -R "$DEST_LOCAL_APP" "$DMG_STAGE_FULL/gg 控制台.app"

if [ -d "$PROJECT_DIR/Source/Resources/Model/KyonLM.mlmodelc" ]; then
    echo "正在將 KyonLM.mlmodelc 複製進完整版安裝包..."
    cp -R "$PROJECT_DIR/Source/Resources/Model/KyonLM.mlmodelc" "$DMG_STAGE_FULL/gg 控制台.app/Contents/Resources/gg.app/Contents/Resources/"
    cp "$PROJECT_DIR/Source/Resources/Model/vocab.txt" "$DMG_STAGE_FULL/gg 控制台.app/Contents/Resources/gg.app/Contents/Resources/"
fi

codesign --force --deep --sign - "$DMG_STAGE_FULL/gg 控制台.app/Contents/Resources/gg.app" 2>/dev/null || true
codesign --force --deep --sign - "$DMG_STAGE_FULL/gg 控制台.app" 2>/dev/null || true
xattr -cr "$DMG_STAGE_FULL/gg 控制台.app"
ln -s /Applications "$DMG_STAGE_FULL/Applications"

DMG_OUTPUT_FULL="$PROJECT_DIR/gg 輸入法 (完整版).dmg"
rm -f "$DMG_OUTPUT_FULL"
hdiutil create -volname "gg 輸入法 (完整版)" -srcfolder "$DMG_STAGE_FULL" -ov -format UDZO "$DMG_OUTPUT_FULL"
rm -rf "$DMG_STAGE_FULL"

echo ""
echo "[發布完成] 已生成所有發布產物："
echo "   1. 完整版 DMG (內嵌神經模型): $DMG_OUTPUT_FULL"
echo "   2. 輕量版 DMG (無神經模型):   $DMG_OUTPUT_LITE"
echo "   3. 獨立模型權重包:            $PROJECT_DIR/KyonLM.mlmodelc.tar.gz"
echo ""
echo "[提示] 您可以將這三個檔案一同上傳至 GitHub Releases 供使用者與開發者自由選擇下載。"
