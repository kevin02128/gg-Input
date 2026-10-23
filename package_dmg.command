#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "正在建置官方 gg.pkg 套件..."
./build_pkg.sh

echo "正在打包發行用 DMG..."
DMG_STAGE="$PROJECT_DIR/build_dmg"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

cp "$PROJECT_DIR/gg.pkg" "$DMG_STAGE/gg.pkg"

DMG_OUTPUT="$PROJECT_DIR/gg.dmg"
rm -f "$DMG_OUTPUT"
hdiutil create -volname "gg" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUTPUT"
rm -rf "$DMG_STAGE"

echo "[完成] gg.dmg 已打包完成，內含官方標準 gg.pkg 安裝套件。"
