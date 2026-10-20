# gg 輸入法 (gg Input Method)

由 **WTF Team** 開發之新一代智慧型台灣繁體中文輸入法，衍生自開放原始碼專案 [McBopomofo (小麥注音)](https://github.com/openvanilla/McBopomofo)，內建專為 Apple Silicon 打造之 **KyonLM 神經語言模型**（由 Apple Neural Engine 硬體加速）與中英混打引擎。

## 關於本專案

本專案是一位大學生的學習與練習作品，在 AI 程式助理（agent）的輔導與協助下，邊做邊學輸入法、Swift / Objective-C++ / C++ 與神經語言模型的開發。專案以開源的 McBopomofo 為基礎進行衍生開發，程式品質與穩定性仍在持續學習與改進中。

歡迎透過 Issue 或 Pull Request 提出建議與指教，也請多包涵。

## 核心特色

- **KyonLM 神經語言模型（ANE 加速）**：10 層因果 Transformer 架構（約 55.5M 參數），即時審查 N-Best 整句語意並融合雙向語意規則，且 100% 本地離線執行。
- **智慧中英混打雙軌預測**：免切換英數模式，敲擊英文字母自動預測英文單字，支援 `Tab` 一鍵補全。
- **盤古之白**：中文與英文、數字交界自動補齊半形空格，排版乾淨美觀。
- **一體化 gg 控制台**：集中管理安裝、覆蓋更新、KyonLM 模型狀態、即時延遲監控與完全解除安裝。

## 系統需求

- **硬體**：搭載 Apple Silicon (M1 / M2 / M3 / M4) 之 Mac
- **作業系統**：macOS 13.0 (Ventura) 或更高版本
- **開發工具**（自行編譯）：Xcode 15.3 / 16.0+、Python 3.9+

## 一般使用者安裝方式

1. 前往 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載最新版本的 `gg 輸入法.dmg`（內建 KyonLM 神經模型）或 `gg 輸入法 (輕量版).dmg`（極簡純詞庫版）。
2. 前往「系統設定 > 鍵盤 > 輸入法」新增並啟用 **gg** 即可開始打字。

## 開發者建置指南

```bash
# 1. 複製專案
git clone https://github.com/kevin02128/gg-Input.git
cd gg-Input

# 2. 初始化 KyonLM 模型目錄
./scripts/setup_model.sh

# 3. 開發熱重載

# 4. 產出 DMG 安裝包
./package_dmg.command
```

若欲自行重新訓練或微調 KyonLM 神經語言模型，請參閱 [`Trainer/README.md`](Trainer/README.md)。

## 隱私與安全承諾

本輸入法不具備任何外連網路權限或追蹤機制，所有打字組字與神經網路運算均於您的 Mac 本機端閉環完成。詳見 [`SECURITY.md`](SECURITY.md)。

## 軟體授權與致謝

本專案採用 [MIT License](LICENSE) 釋出。特別感謝 OpenVanilla / McBopomofo 團隊與相關開源社群，完整第三方授權列表請參閱 [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md)，訓練語料來源與資料授權請參閱 [`DATA_LICENSE.md`](DATA_LICENSE.md)。
