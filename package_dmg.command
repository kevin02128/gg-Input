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

# 簽章輔助函式：由內而外進行完整簽章並驗證
sign_bundle_recursively() {
    local app_path="$1"
    echo "  -> 正在清理延伸屬性與簽章：$(basename "$app_path")"
    xattr -cr "$app_path"
    if [ -d "$app_path/Contents/Resources/gg.app" ]; then
        xattr -cr "$app_path/Contents/Resources/gg.app"
        codesign --force --deep --sign - "$app_path/Contents/Resources/gg.app"
        codesign --verify --deep --strict "$app_path/Contents/Resources/gg.app"
    fi
    codesign --force --deep --sign - "$app_path"
    codesign --verify --deep --strict "$app_path"
    echo "  -> 簽章驗證通過 (Valid on disk)"
}

# 3. 製作客戶端發布用的 DMG 磁碟映像檔
echo "正在打包【輕量版】DMG（無內嵌神經模型，約 9MB）..."
DMG_STAGE_LITE="$PROJECT_DIR/build_dmg_lite"
rm -rf "$DMG_STAGE_LITE"
mkdir -p "$DMG_STAGE_LITE"

cp -R "$DEST_LOCAL_APP" "$DMG_STAGE_LITE/gg 控制台.app"
sign_bundle_recursively "$DMG_STAGE_LITE/gg 控制台.app"
ln -s /Applications "$DMG_STAGE_LITE/Applications"

DMG_OUTPUT_LITE="$PROJECT_DIR/gg.lite.dmg"
rm -f "$DMG_OUTPUT_LITE"
hdiutil create -volname "gg-lite" -srcfolder "$DMG_STAGE_LITE" -ov -format UDZO "$DMG_OUTPUT_LITE"
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

if [ ! -s "$PROJECT_DIR/Source/Resources/Model/KyonLM.mlmodelc/weights/weight.bin" ]; then
    echo "[錯誤] 找不到完整 KyonLM 權重，無法建立完整版與獨立模型包。" >&2
    exit 1
fi
tar -czf "$PROJECT_DIR/KyonLM.mlmodelc.tar.gz" -C "$PROJECT_DIR/Source/Resources/Model" KyonLM.mlmodelc

sign_bundle_recursively "$DMG_STAGE_FULL/gg 控制台.app"
ln -s /Applications "$DMG_STAGE_FULL/Applications"

DMG_OUTPUT_FULL="$PROJECT_DIR/gg.dmg"
rm -f "$DMG_OUTPUT_FULL"
hdiutil create -volname "gg" -srcfolder "$DMG_STAGE_FULL" -ov -format UDZO "$DMG_OUTPUT_FULL"
rm -rf "$DMG_STAGE_FULL"

echo ""
echo "[發布完成] 已生成所有發布產物（並通過 codesign 驗證）："
echo "   1. 完整版 DMG (Release 上傳檔): $DMG_OUTPUT_FULL"
echo "   2. 輕量版 DMG (Release 上傳檔): $DMG_OUTPUT_LITE"
echo "   3. 獨立模型權重包:             $PROJECT_DIR/KyonLM.mlmodelc.tar.gz"
echo ""
echo "[提示] 可將 gg.dmg 與 gg.lite.dmg 上傳至 GitHub Releases 替換舊檔。"
