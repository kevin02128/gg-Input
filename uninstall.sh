#!/bin/bash
set -e

echo "正在解除安裝 gg 輸入法..."

# 1. 結束正在運行的 gg 進程
killall -9 gg 2>/dev/null || true
pkill -9 -f gg.app 2>/dev/null || true

# 2. 移除使用者目錄與全域目錄內的 gg.app
REMOVED=0
USER_APP="$HOME/Library/Input Methods/gg.app"
SYSTEM_APP="/Library/Input Methods/gg.app"

if [ -d "$USER_APP" ]; then
    rm -rf "$USER_APP"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$USER_APP" 2>/dev/null || true
    echo "[完成] 已刪除使用者層級輸入法：$USER_APP"
    REMOVED=1
fi

if [ -d "$SYSTEM_APP" ]; then
    if [ -w "/Library/Input Methods" ]; then
        rm -rf "$SYSTEM_APP"
    else
        echo "[提示] 需要管理員權限移除全域輸入法模組，請輸入密碼："
        sudo rm -rf "$SYSTEM_APP"
    fi
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$SYSTEM_APP" 2>/dev/null || true
    echo "[完成] 已刪除系統層級輸入法：$SYSTEM_APP"
    REMOVED=1
fi

if [ $REMOVED -eq 0 ]; then
    echo "[資訊] 未在系統輸入法目錄中找到 gg.app"
fi

# 3. 詢問是否清理偏好設定與自訂詞庫
read -p "是否同時清除自訂詞庫與設定檔 (y/N)? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/Library/Application Support/gg"
    rm -f "$HOME/Library/Preferences/com.wtf.inputmethod.gg.plist"
    defaults delete com.wtf.inputmethod.gg 2>/dev/null || true
    echo "[完成] 已清除自訂詞庫與設定檔"
fi

echo ""
echo "[完成] 解除安裝完成！"
echo "[提示] 若選單列仍殘留圖示，請至「系統設定 > 鍵盤 > 輸入方式」將 gg 輸入法點選「-」移除或登出重新登入即可。"
