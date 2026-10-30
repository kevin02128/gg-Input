#!/bin/bash
set -e

echo "正在完整解除安裝 gg 輸入法及歷史殘留模組..."

# 1. 先透過 TIS API 切換到英文鍵盤並停用 gg，確認成功後才移除檔案
GG_EXECUTABLE="$HOME/Library/Input Methods/gg.app/Contents/MacOS/gg"
if [ ! -x "$GG_EXECUTABLE" ]; then
    GG_EXECUTABLE="/Library/Input Methods/gg.app/Contents/MacOS/gg"
fi
if [ -x "$GG_EXECUTABLE" ] && ! "$GG_EXECUTABLE" uninstall; then
    echo "[錯誤] 無法切換輸入來源或停用 gg；未移除任何檔案。"
    exit 1
fi

killall -TERM gg Anev 2>/dev/null || true

# 2. 移除使用者目錄與全域目錄內的 gg.app、Anev.app 與 gg.localized
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

for user_app in "$HOME/Library/Input Methods/gg.app" "$HOME/Library/Input Methods/Anev.app"; do
    if [ -d "$user_app" ]; then
        rm -rf "$user_app"
        [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$user_app" 2>/dev/null || true
        echo "[完成] 已刪除使用者層級輸入法：$user_app"
    fi
done

NEED_SUDO=0
for sys_target in "/Library/Input Methods/gg.app" "/Library/Input Methods/Anev.app" "/Library/Input Methods/gg.localized"; do
    if [ -e "$sys_target" ]; then
        NEED_SUDO=1
        break
    fi
done

if [ $NEED_SUDO -eq 1 ]; then
    echo "[提示] 需要管理員權限移除全域系統輸入法模組，請輸入密碼："
    sudo rm -rf "/Library/Input Methods/gg.app" "/Library/Input Methods/Anev.app" "/Library/Input Methods/gg.localized"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -u "/Library/Input Methods/gg.app" 2>/dev/null || true
        "$LSREGISTER" -u "/Library/Input Methods/Anev.app" 2>/dev/null || true
        "$LSREGISTER" -u "/Library/Input Methods/gg.localized/gg.app" 2>/dev/null || true
    fi
    echo "[完成] 已清除系統全域層級之輸入法檔案"
fi

# 解除註冊 Xcode DerivedData 暫存目錄
if [ -x "$LSREGISTER" ]; then
    for derived in "$HOME"/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/*/gg.app; do
        [ -d "$derived" ] && "$LSREGISTER" -u "$derived" 2>/dev/null || true
    done
    for derived_anev in "$HOME"/Library/Developer/Xcode/DerivedData/anev-*/Build/Products/*/Anev.app; do
        [ -d "$derived_anev" ] && "$LSREGISTER" -u "$derived_anev" 2>/dev/null || true
    done
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

# 5. 刷新選單列與系統輸入法快取
rm -f "$(getconf DARWIN_USER_CACHE_DIR)"com.apple.IntlDataCache.le* 2>/dev/null || true
killall -9 cfprefsd TextInputMenuAgent TextInputSwitcher CursorUIViewService systemsettingsagent 2>/dev/null || true

echo ""
echo "[完成] gg 輸入法已徹底解除安裝！"
