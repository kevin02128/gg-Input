# gg 輸入法 (gg Input Method)

衍生自開放原始碼專案 [McBopomofo (小麥注音)](https://github.com/openvanilla/McBopomofo)，內建專為 Apple Silicon 打造之 **KyonLM 神經語言模型**（由 Apple Neural Engine 硬體加速）與中英混打引擎。

## 關於本專案

本專案是一位大學生的學習作品，自用為目的。
在 AI 程式助理（agent）的輔導與協助下。專案以開源的 McBopomofo 為基礎進行開發。

## 核心特色

- **KyonLM 神經語言模型（ANE 加速）**：10 層因果 Transformer 架構（約 55.5M 參數），本地離線執行。
- **智慧中英混打雙軌預測**：免切換英數模式，敲擊英文字母自動預測英文單字，支援 `Tab` 一鍵補全。
- **盤古之白**：中文與英文、數字交界自動補齊半形空格，排版乾淨美觀。

## 系統需求

- **硬體**：搭載 Apple Silicon 之 Mac
- **作業系統**：macOS 13.0 (Ventura) 或更高版本
- **開發工具**（自行編譯）：Xcode 16.0+、Python 3.9+

## 一般使用者安裝方式

1. 前往 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載安裝映像檔：
   - **`gg.dmg`**（推薦）：完整版，內建 KyonLM 神經語言模型。
   - **`gg.lite.dmg`**：輕量版，極簡純詞庫，不含神經模型。
2. 開啟 DMG 檔案，將 **`gg 控制台.app`** 拖曳至 **`Applications`（應用程式）** 資料夾。
3. 開啟「gg 控制台.app」，點擊「同意並安裝 gg 輸入法」。
4. 前往 macOS「系統設定 > 鍵盤 > 文字輸入 > 輸入來源（編輯）」點擊 `+`，在繁體中文清單中新增並啟用 **gg** 即可開始打字。

### 首次開啟若被 macOS 阻擋（Gatekeeper 處理指引）

由於未加入 Apple Developer Program 商業開發者證書進行官方伺服器公證（Notarization），macOS 首次開啟由瀏覽器下載的 App 時會啟動安全防護機制：

* **情況一：提示「無法驗證開發者」**
  - 前往 macOS **「系統設定」>「隱私權與安全性」**。
  - 向下捲動至「安全性」區塊，會看到「已阻擋使用『gg 控制台.app』」提示。
  - 點擊旁邊的 **「強制打開（Open Anyway）」** 並輸入 Mac 密碼即可正常啟動。
  *(註：macOS 15 Sequoia 起已取消在 Finder 右鍵點選「打開」的繞過機制，請依上述系統設定途徑放行)*

* **情況二：提示「已損毀，您應該將它丟到垃圾桶」**
  - 此為 macOS 針對未公證網路下載檔案強制施加之隔離標籤（Quarantine），檔案本身並未損毀。
  - 開啟 Mac 內建的 **終端機（Terminal）**，貼上並執行以下單行指令清除隔離標籤：
    ```bash
    xattr -cr "/Applications/gg 控制台.app"
    ```
  - 執行後即可正常雙擊打開「gg 控制台.app」。
  *(若安裝後輸入法本體亦遇隔離阻擋，可對輸入法執行：`xattr -cr "$HOME/Library/Input Methods/gg.app"`)*

## 開發者建置指南

若欲自行重新訓練或微調 KyonLM 神經語言模型，請參閱 [`Trainer/README.md`](Trainer/README.md)。

## 隱私與安全承諾

本輸入法不具備任何外連網路權限或追蹤機制，所有打字組字與神經網路運算均於您的 Mac 本機端閉環完成。詳見 [`SECURITY.md`](SECURITY.md)。

## 軟體授權與致謝

本專案採用 [MIT License](LICENSE) 釋出。特別感謝 OpenVanilla / McBopomofo 團隊與相關開源社群，完整第三方授權列表請參閱 [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md)，訓練語料來源與資料授權請參閱 [`DATA_LICENSE.md`](DATA_LICENSE.md)。
