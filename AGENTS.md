# AGENTS.md

本文件為 AI 編程助手（如 Antigravity / Copilot）在 `gg` 輸入法專案中工作的最高指導原則。

---

## 🚨 最高執行鐵律 (Strict Execution Policy - MUST FOLLOW)

1. **禁止未經允許修改或執行 (Plan-First Gate)**：
   - 當使用者提出新需求、Bug 修復、按鍵調整或架構詢問時，**絕對禁止**直接修改任何程式碼或資料檔，也**絕對禁止**未經授權直接執行 `./build_pkg.command`、`git commit` 或 `git push`。
2. **強制兩階段工作流 (Two-Phase Workflow)**：
   - **第一階段（唯讀掃描與提案）**：僅允許讀取檔案與搜尋程式碼。找出問題根因（Root Cause）後，必須使用**繁體中文**向使用者輸出結構化的【技術修改計畫書】（包含：根因分析、預計修改檔案、邊界條件防呆、預計新增的單元測試）。最後必須停下來詢問：「請確認以上計畫是否無誤，確認後我再開始實作。」
   - **第二階段（授權後實作）**：只有在收到使用者明確回覆「好」、「可以」、「開始執行」等同意字眼後，才允許修改檔案、執行 `xcodebuild test` 與 `./build_pkg.command`。
3. **嚴禁未經指示執行 git push (Local Only Rule)**：
   - 所有程式碼變更與 Commit 僅保留於本地 Git 儲存庫。
   - 除非使用者發出明確指令（如「推送到 GitHub」、「git push」），否則**絕對禁止**主動推送遠端倉庫，完全由使用者決定何時發布。

---

## 🔬 嚴謹工程與深度技術審查原則 (Technical Rigor & Deep Review Rules)

在進行程式碼實作、架構設計與規格文件撰寫時，必須具備頂級系統工程師的嚴謹度與顯微鏡級的細節意識，嚴禁任何浮誇、假定或模糊陳述：

### 1. 技術誠實與不浮誇原則 (Technical Honesty & Precision)
- **實作與描述必須 100% 吻合**：絕不宣稱未實作的演算法。若演算法僅使用 Unigram 單字對數機率在讀音網格上動態規劃，就必須精確稱為「DAG 最長路徑搜尋」，嚴禁虛報為「含 Bigram 轉移項的 HMM」。
- **演算法複雜度嚴禁矛盾**：首字母分桶後若進行線性前綴掃描，複雜度即為 $O(K)$（$K$ 為同桶詞數），嚴禁誇大為 $O(1)$。
- **數學與物理量精確定義**：涉及機率、衰減或時間常數時必須推導明確。指數衰減時間常數 $\tau = 5400\text{ s}$ 與半衰期 $t_{1/2} = \tau \ln 2 \approx 3743\text{ s}$ 差了一個 $\ln 2$（約 1.44 倍），概念絕對不能混用。
- **捨棄無法證實的行銷對比**：移除「100% 達成」、「商業輸入法數百 MB 遙測」等情緒化形容，一律改用具體測試條件（macOS 版本、硬體架構、測試工具）的實測數據與客觀已知限制。

### 2. 編譯器與 Runtime 邊界防禦 (Compiler & Runtime Realities)
- **警惕 Release 剝離 `assert`**：Swift 的 `assert(...)` 在 Release 最佳化編譯（`-O`）會被編譯器完全移除。核心組字資料流、網格回溯與錯誤處理**絕不能僅依賴 `assert` 防守**，必須實作明確的保底機制（Fallback）與防呆分支，防止發行版發生靜默丟字。
- **最佳化目標與回溯計分一致性**：前向動態規劃所最大化的量（如包含手動選字加權的分數），在反向回溯統計時必須累加相同的分數項，嚴禁出現前向最佳化與反向回傳總分不一致的瑕疵。

### 3. macOS 系統與環境真實邊界 (macOS Platform Depth)
- **零外部依賴安裝腳本**：安裝（`postinstall`）與卸載腳本**嚴禁呼叫 `/usr/bin/python3`**。在乾淨 macOS 系統上未安裝 Xcode Command Line Tools 時，執行 `/usr/bin/python3` 會觸發系統彈窗要求安裝開發者工具，破壞使用者體驗。必須優先使用已編譯的 Swift 原生二進位或系統內建工具（如 `/usr/bin/plutil`、`/usr/libexec/PlistBuddy`）。
- **精確釐清安全與沙盒邊界**：清楚區分 App Sandbox Entitlements 與 macOS TCC。若輸入法尚未配置 entitlements 啟用沙盒，不得聲稱「受沙盒封鎖無法存取檔案」；「無網路」若是由程式碼未引入網路 API 達成，必須老實註明，不可誤導為作業系統硬性沙盒阻斷。
- **暫存狀態生命週期重置**：涉及自動排版或預測的跨鍵擊狀態（如 `lastCommittedChar`），必須在 App 焦點切換（`activateServer`/`deactivateServer`）、滑鼠移動游標（`commitComposition`）及空緩衝區換行/方向鍵時徹底重置，防止過期狀態污染全新輸入位置。
- **專業開發者環境感知**：針對終端機（Terminal, iTerm2 等）與程式碼編輯器（VS Code, Xcode 等），應主動提供 Bundle ID 黑名單以抑制中英自動空格，避免破壞程式碼語法與 Shell 指令。

### 4. 領域極致邊界推演 (Edge-Case Deduction)
- **修飾鍵與 Shift 資訊不可被提前抹除**：設計音韻或相衝規則時，必須推演大小寫與 Shift 鍵情境。例如硬體機架單位 `1U`、`2U` 若在音節校驗前被強制轉為小寫，會被誤判為合法注音 `1u`（ㄅㄧ）或 `2u`（ㄉㄧ），導致無法輸入英文規格。
- **大千注音鍵位衝突預防**：純數字輸入（如 `10` 對應注音 `ㄅㄢ`）必須有明確的覆寫路徑（如 `Option + 數字` 直接輸出半形數字）。

### 5. 開源血統與授權誠信 (Open Source Integrity)
- 專案凡引用、衍生或改寫自開源社群（如 McBopomofo 小麥注音、OpenVanilla、OpenCC、SQLite.swift），必須在文件與程式碼中給予完整、誠實的版權聲明與致謝，明確記錄核心參數與演算法的歷史脈絡。

---

## ⚡ Token 節省與高效率工作規範 (Token Efficiency & Speed Rules)

為了將上下文視窗 (Context Window) 與 Token 消耗降至最低，並最大化執行速度，請嚴格遵守以下 5 項操作限制：

### 1. 嚴禁讀取大型字典與二進位產物 (Large File Blacklist)
- **絕對禁止**對 `Source/Data/` 下的大型資料檔執行完整讀取 (`view_file` / `cat`)，包含但不限於：
  - `Source/Data/data.txt`
  - `Source/Data/data-plain-bpmf.txt`
  - `Source/Data/BPMFMappings.txt`
  - `Source/Data/phrase.occ`
  - `Source/Data/associated-phrases-v2.txt`
  - 任何 `.mlmodelc`、`build/`、`DerivedData/` 或 `.dmg` 檔案。
- **替代方案**：若需查詢或驗證特定字詞映射，**只能使用精確搜尋指令**（如 `grep -n "關鍵字" Source/Data/BPMFPunctuations.txt | head -n 20`），嚴禁將超過 50 行的字典內容載入對話中。

### 2. 精準局部讀檔與局部修改 (Targeted Read & Surgical Edit)
- **先搜後讀**：處理超過 200 行的程式碼檔案（如 `InputMethodController.swift`、`KeyHandler.mm`、`MixedInputManager.swift`）時，**禁止一次讀取整個檔案**。必須先用 `grep` 找出目標函數或關鍵字的行號，再僅讀取該行號前後 40～60 行的區間。
- **局部替換**：修改程式碼時，優先使用局部區塊替換工具（Diff / Replace），**禁止重寫或輸出整個檔案的完整內容**。

### 3. 靜默化編譯與單一測試執行 (Quiet Build & Focused Testing)
- `xcodebuild` 預設會吐出數千行編譯訊息，嚴重浪費 Token。執行建置或測試時：
  - **必須加上 `-quiet` 參數**，或僅擷取錯誤與測試結果摘要（例如：`xcodebuild test -project gg.xcodeproj -scheme gg -destination 'platform=macOS' -quiet`）。
  - 在開發與除錯階段，**優先只跑當前修改相關的單一測試函數**（使用 `-only-testing:ggTests/KeyHandlerBopomofoTests/測試函數名稱`），全部改完最後才跑一次全套測試。

### 4. 大千注音鍵位速查表（內建記憶，免查原始碼）
請直接使用以下大千（Standard）鍵位映射進行邏輯推演，**無須為了確認鍵位而去翻閱 `Mandarin.cpp` 原始碼**：
- **聲母 (Initials)**：`1`(ㄅ) `q`(ㄆ) `a`(ㄇ) `z`(ㄈ) `2`(ㄉ) `w`(ㄊ) `s`(ㄋ) `x`(ㄌ) `e`(ㄍ) `d`(ㄎ) `c`(ㄏ) `r`(ㄐ) `f`(ㄑ) `v`(ㄒ) `5`(ㄓ) `t`(ㄔ) `g`(ㄕ) `b`(ㄖ) `y`(ㄗ) `h`(ㄘ) `n`(ㄙ)
- **介音 (Medials)**：`u`(ㄧ) `j`(ㄨ) `m`(ㄩ)
- **韻母 (Finals)**：`8`(ㄚ) `i`(ㄛ) `k`(ㄜ) `,`(ㄝ) `9`(ㄞ) `o`(ㄟ) `l`(ㄠ) `.`(ㄡ) `0`(ㄢ) `p`(ㄣ) `;`(ㄤ) `/`(ㄥ) `-`(ㄦ)
- **聲調 (Tones)**：`Space`(一聲) `6`(二聲 ˊ) `3`(三聲 ˇ) `4`(四聲 ˋ) `7`(輕聲 ˙)

### 5. 極簡白話溝通格式 (Concise Communication)
- **禁止重複貼出原始碼**：除非使用者要求，否則在報告中**不要大段貼出剛寫好的程式碼**（只需列出修改了哪個檔案、哪個函數、核心邏輯是什麼）。
- **白話且精煉**：向使用者提出【修改計畫書】或【完成報告】時，請用最直覺的白話文與簡短條列呈現，控制在 300～500 字以內，省略所有客套話與冗長的背景鋪陳。

---

## Project Overview

`gg` 輸入法是基於 McBopomofo（小麥注音）深度改造的 macOS 繁體中文大千注音與中英雙軌智慧輸入法。
除支援傳統注音外，核心特色包含：
1. **中英雙軌並行預測 (`MixedInputManager`)**：同時考量英文與注音合法性，支援 `Tab` 補全英文、聲調鍵觸發中文、注音語法相衝時自動鎖定純英文模式，以及科技英數短字（如 `4K`, `3D`, `5G`, `8K`, `M1`, `B2B`）直出。
2. **直覺化按鍵與標點邏輯**：按住 `Option ⌥` 強制 100% 輸出美式半形數字與符號（阻斷 macOS 原生冷門歐文符號如 `÷`, `æ`）。
3. **一鍵官方安裝套件**：透過 `build_pkg.command` 自動編譯並封裝為官方標準 `gg.pkg`。

專案採用三層架構：Swift (UI / 雙軌狀態管理)、Objective-C++ (橋接層)、C++ (核心注音與語言模型引擎)，基於 macOS Input Method Kit (IMK) 框架。

---

## Building, Reloading, and Packaging

### Xcode Project Structure

主要 **targets**：
- `gg`: 主輸入法 bundle
- `Data`: 字典資料編譯目標 (`Source/Data/Makefile`)
- `ggTests`: Swift 單元測試套件（包含雙軌、英數短字與連續長句迴歸測試）

### 常用開發與部署指令（需經使用者授權後執行）

```bash
# 1. 執行完整單元測試（修改程式碼後必跑）
xcodebuild test -project gg.xcodeproj -scheme gg -destination 'platform=macOS' -quiet

# 2. 重新編譯並打包官方標準安裝套件 (gg.pkg)
./build_pkg.command

# 3. 單獨重新生成字典檔（若有修改 Source/Data/ 下的檔案）
cd Source/Data
make all           # 生成 data.txt, data-plain-bpmf.txt, associated-phrases-v2.txt
make sort          # 使用 LC_ALL=C 進行二進位排序（極重要，確保二分搜尋正確）
make check         # 驗證字典資料完整性
