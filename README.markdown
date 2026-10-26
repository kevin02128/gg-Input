# gg 輸入法 (gg Input Method)
注音輸入法，具備中英混打。

## 關於本專案
大學生的學習與開源作品，在 AI 助理的引導下完成全專案現代化架構重構與演算法優化。
核心架構採純 Swift，支援 Apple Neural Engine (ANE) 自研模型接入準備。

## 系統需求
- **硬體**：搭載 Apple Silicon 之 Mac (M1/M2/M3/M4 系列)
- **作業系統**：macOS 13.0 (Ventura) 或更高版本
- **開發工具**（自行編譯）：Xcode 16.0+、Python 3.9+

## 一般使用者安裝方式
1. 前往 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載官方安裝套件 **`gg.pkg`**。
2. 雙擊 **`gg.pkg`**，按照 macOS 官方安裝精靈引導完成安裝（約 5 秒即可完成自動佈署與註冊）。
3. 前往 macOS「系統設定 > 鍵盤 > 文字輸入 > 輸入來源（編輯）」點擊 `+`，在繁體中文清單中新增並啟用 **gg** 即可開始打字。

## 解除安裝方式
- **選單一鍵解除安裝（推薦）**：
  在螢幕右上角點開 `gg` 輸入法選單 -> 點選 **「解除安裝 gg 輸入法…」**，依照彈窗指示確認後，系統將自動切換回預設英文鍵盤並完全刪除應用程式與進程。
- **終端機指令解除安裝**：
  亦可在本專案目錄執行 `./uninstall.sh` 完成乾淨卸載。

## 隱私與安全承諾
本輸入法不具備任何外連網路權限或追蹤機制，所有打字組字均於您的 Mac 本機端閉環完成。詳見 [`SECURITY.md`](docs/SECURITY.md)。

## 軟體授權與致謝
本專案採用 [MIT License](LICENSE) 釋出。特別感謝 OpenVanilla / McBopomofo 團隊與相關開源社群，完整第三方授權列表請參閱 [`ACKNOWLEDGEMENTS.md`](docs/ACKNOWLEDGEMENTS.md)。
