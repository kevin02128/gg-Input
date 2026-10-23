#!/bin/bash
# ==============================================================================
# setup_model.sh — 準備 KyonLM Core ML 模型目錄與下載腳本
# 用途：解決 GitHub 單一檔案 100MB 限制。
#       若本機尚未存在完整 KyonLM.mlmodelc（107MB），會嘗試自 GitHub Releases 下載；
#       若處於離線或 CI 測試環境，會自動建立結構骨架以確保 Xcode 專案 100% 順利編譯。
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="$PROJECT_DIR/Source/Resources/Model"
MLMODELC_DIR="$MODEL_DIR/KyonLM.mlmodelc"
WEIGHT_FILE="$MLMODELC_DIR/weights/weight.bin"

REPO_URL="https://github.com/kevin02128/gg-Input"
RELEASE_ASSET_URL="$REPO_URL/releases/latest/download/KyonLM.mlmodelc.tar.gz"

mkdir -p "$MODEL_DIR"

if [ -f "$WEIGHT_FILE" ] && [ $(stat -f%z "$WEIGHT_FILE" 2>/dev/null || echo 0) -gt 1000000 ]; then
    echo "[資訊] KyonLM.mlmodelc 模型權重已就緒 ($MLMODELC_DIR)。"
    exit 0
fi

echo "[資訊] 本機尚未偵測到完整的 KyonLM.mlmodelc 權重，嘗試從 GitHub Releases 下載..."
TMP_TAR="$(mktemp "${TMPDIR:-/tmp}/KyonLM.mlmodelc.XXXXXX.tar.gz")"
trap 'rm -f "$TMP_TAR"' EXIT

if curl -fL --connect-timeout 10 --max-time 180 "$RELEASE_ASSET_URL" -o "$TMP_TAR" 2>/dev/null; then
    echo "[資訊] 下載成功，正在驗證模型封存檔..."
    if ! tar -tzf "$TMP_TAR" >/dev/null; then
        echo "[錯誤] 模型封存檔無法讀取。" >&2
        exit 1
    fi
    if tar -tzf "$TMP_TAR" | awk 'BEGIN { bad=0 } /^\// || /(^|\/)\.\.($|\/)/ { bad=1 } END { exit bad }'; then
        echo "[資訊] 封存檔路徑檢查通過，正在解壓縮..."
    else
        echo "[錯誤] 模型封存檔含有不安全路徑。" >&2
        exit 1
    fi
    tar -xzf "$TMP_TAR" -C "$MODEL_DIR"
    if [ ! -s "$WEIGHT_FILE" ]; then
        echo "[錯誤] 解壓後缺少模型權重或檔案為空。" >&2
        exit 1
    fi
    echo "[完成] KyonLM.mlmodelc 已安裝完成！"
    exit 0
else
    echo "[提示] 尚未從遠端取得 Release 權重包，建立輕量結構骨架以供 Xcode 編譯與單元測試..."
    mkdir -p "$MLMODELC_DIR/weights"
    mkdir -p "$MLMODELC_DIR/analytics"
    if [ ! -f "$MLMODELC_DIR/metadata.json" ]; then
        echo '{"shortDescription":"KyonLM placeholder for build","author":"wtf"}' > "$MLMODELC_DIR/metadata.json"
    fi
    touch "$MLMODELC_DIR/model.mil"
    touch "$MLMODELC_DIR/coremldata.bin"
    touch "$WEIGHT_FILE"
    echo "[完成] 結構骨架已建立，Xcode 可正常編譯（執行期將自動退回規則與詞庫融合模式，或讀取 ~/Library/Application Support/gg/Models/KyonLM.mlmodelc）。"
fi
