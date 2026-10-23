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

1. 前往 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載官方安裝套件 **`gg.pkg`**（或由 `gg.dmg` 內取得）。
2. 雙擊 **`gg.pkg`**，按照 macOS 官方安裝精靈引導完成安裝（約 5 秒即可完成自動佈署與註冊）。
3. 前往 macOS「系統設定 > 鍵盤 > 文字輸入 > 輸入來源（編輯）」點擊 `+`，在繁體中文清單中新增並啟用 **gg** 即可開始打字。

## 解除安裝方式

- **選單一鍵解除安裝（推薦）**：
  在螢幕右上角點開 `gg` 輸入法選單 -> 點選 **「解除安裝 gg 輸入法…」**，依照彈窗指示確認後，系統將自動切換回預設英文鍵盤並完全刪除應用程式與進程。
- **終端機指令解除安裝**：
  亦可在本專案目錄執行 `./uninstall.sh` 完成乾淨卸載。

## 開發者建置指南

若欲自行重新訓練或微調 KyonLM 神經語言模型，請參閱 [`Trainer/README.md`](Trainer/README.md)。

## 隱私與安全承諾

本輸入法不具備任何外連網路權限或追蹤機制，所有打字組字與神經網路運算均於您的 Mac 本機端閉環完成。詳見 [`SECURITY.md`](SECURITY.md)。

## 軟體授權與致謝

本專案採用 [MIT License](LICENSE) 釋出。特別感謝 OpenVanilla / McBopomofo 團隊與相關開源社群，完整第三方授權列表請參閱 [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md)，訓練語料來源與資料授權請參閱 [`DATA_LICENSE.md`](DATA_LICENSE.md)。
