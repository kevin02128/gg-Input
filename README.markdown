# gg 輸入法 (gg Input Method)
注音輸入法，具備中英混打。

## 關於本專案
大學生的學習與開源作品，在 AI 助理的引導下完成全專案現代化架構重構與演算法優化。
核心架構採純 Swift 原生高靈敏圖論組字（Viterbi + N-gram Context Walk），追求極致低延遲、小體積與無干擾輸入體感。

## 系統需求
- **硬體**：Mac (Apple Silicon 或 Intel 系列)
- **作業系統**：macOS 13.0 (Ventura) 或更高版本
- **開發工具**（自行編譯）：Xcode 15.0+、Swift 5.9+

## 一般使用者安裝方式
1. 直接下載官方安裝套件 [**`gg.pkg` (v0.4.0)**](https://github.com/kevin02128/gg-Input/raw/main/gg.pkg)（亦可至 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載）。
2. 雙擊 **`gg.pkg`**，依照 macOS 安裝精靈完成安裝。登入中的桌面帳號會自動註冊並啟用 gg 注音輸入模式。
3. 若安裝後選單列仍未出現 **gg**，前往 macOS「系統設定 > 鍵盤 > 文字輸入 > 編輯」，點擊 `+`，在繁體中文清單新增 **gg**。

## 解除安裝方式
- **選單一鍵解除安裝（推薦）**：
  在螢幕右上角點開 `gg` 輸入法選單 -> 點選 **「解除安裝 gg 輸入法…」**，依照彈窗指示確認後，系統將自動切換回預設英文鍵盤並完全刪除應用程式與進程。
- **終端機指令解除安裝**：
  亦可在本專案目錄執行 `./uninstall.sh` 完成乾淨卸載。

## 隱私與安全承諾
本輸入法不具備任何外連網路權限或追蹤機制，所有打字組字均於您的 Mac 本機端閉環完成。詳見 [`SECURITY.md`](docs/SECURITY.md)。

## 軟體授權與致謝
本專案自 v0.3 起採用 [MIT License](LICENSE) 釋出。
- **授權過渡聲明**：v0.3（原內部規劃標號 v3.0）之前的所有提交（含 `legacy-coreml-experiment` 標籤）依當時的 LICENSE（GNU General Public License v3.0, GPL-3.0）散佈；自 v0.3 起的程式碼採 MIT License 發行。
- 特別感謝 OpenVanilla / McBopomofo 團隊與相關開源社群，第三方資料與字典（包含政府資料開放授權 OGDL-Taiwan-1.0 統計）之完整逐檔歸屬請參閱 [`NOTICE`](NOTICE)。
