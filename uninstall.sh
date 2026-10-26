#!/bin/bash
set -e

echo "正在解除安裝 gg 輸入法..."

# 1. 結束正在運行的進程
killall -9 gg 2>/dev/null || true
pkill -9 -f gg.app 2>/dev/null || true

# 2. 移除使用者目錄與全域目錄內的 gg.app
REMOVED=0
app_path="$HOME/Library/Input Methods/gg.app"
if [ -d "$app_path" ]; then
    rm -rf "$app_path"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$app_path" 2>/dev/null || true
    echo "[完成] 已刪除使用者層級輸入法：$app_path"
    REMOVED=1
fi

sys_path="/Library/Input Methods/gg.app"
if [ -d "$sys_path" ]; then
    if [ -w "/Library/Input Methods" ]; then
        rm -rf "$sys_path"
    else
        echo "[提示] 需要管理員權限移除全域輸入法模組，請輸入密碼："
        sudo rm -rf "$sys_path"
    fi
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$sys_path" 2>/dev/null || true
    echo "[完成] 已刪除系統層級輸入法：$sys_path"
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
    rm -f "$HOME/Library/Preferences/com.kevin.inputmethod.gg.plist"
    defaults delete com.kevin.inputmethod.gg 2>/dev/null || true
    echo "[完成] 已清除自訂詞庫與設定檔"
fi

echo ""
echo "[完成] 解除安裝完成！"
echo "[提示] 若選單列仍殘留圖示，請至「系統設定 > 鍵盤 > 輸入方式」將 gg 輸入法點選「-」移除或登出重新登入即可。"
