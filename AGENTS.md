# AGENTS.md

本文件為 AI 編程助手（如 Antigravity / Copilot）在 `gg` 輸入法專案中工作的最高指導原則。

---

## 🚨 最高執行鐵律 (Strict Execution Policy - MUST FOLLOW)

1. **禁止未經允許修改或執行 (Plan-First Gate)**：
   - 當使用者提出新需求、Bug 修復、按鍵調整或架構詢問時，**絕對禁止**直接修改任何程式碼或資料檔，也**絕對禁止**未經授權直接執行 `./dev_reload.sh`、`./build_pkg.command`、`git commit` 或 `git push`。
2. **強制兩階段工作流 (Two-Phase Workflow)**：
   - **第一階段（唯讀掃描與提案）**：僅允許讀取檔案與搜尋程式碼。找出問題根因（Root Cause）後，必須使用**繁體中文**向使用者輸出結構化的【技術修改計畫書】（包含：根因分析、預計修改檔案、邊界條件防呆、預計新增的單元測試）。最後必須停下來詢問：「請確認以上計畫是否無誤，確認後我再開始實作。」
   - **第二階段（授權後實作）**：只有在收到使用者明確回覆「好」、「可以」、「開始執行」等同意字眼後，才允許修改檔案、執行 `xcodebuild test`、`./dev_reload.sh` 與 `./build_pkg.command`。

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
- **先搜後讀**：處理超過 200 行的程式碼檔案（如 `InputMethodController.swift`、`KeyHandler.mm`、`WTFMixedInputManager.swift`）時，**禁止一次讀取整個檔案**。必須先用 `grep` 找出目標函數或關鍵字的行號，再僅讀取該行號前後 40～60 行的區間。
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
1. **中英雙軌並行預測 (`WTFMixedInputManager`)**：同時考量英文與注音合法性，支援 `Tab` 補全英文、聲調鍵觸發中文、注音語法相衝時自動鎖定純英文模式，以及科技英數短字（如 `4K`, `3D`, `5G`, `8K`, `M1`, `B2B`）直出。
2. **直覺化按鍵與標點邏輯**：按住 `Option ⌥` 強制 100% 輸出美式半形數字與符號（阻斷 macOS 原生冷門歐文符號如 `÷`, `æ`）。
3. **一鍵官方安裝套件**：透過 `build_pkg.command` 自動編譯並封裝為官方標準 `gg.pkg`。

專案採用三層架構：Swift (UI / 雙軌狀態管理)、Objective-C++ (橋接層)、C++ (核心注音與語言模型引擎)，基於 macOS Input Method Kit (IMK) 框架。

---

## Building, Reloading, and Packaging

### Xcode Project Structure

主要 **targets**：
- `gg`: 主輸入法 bundle
- `ggInstaller`: 安裝程式
- `Data`: 字典資料編譯目標 (`Source/Data/Makefile`)
- `ggTests`: Swift 單元測試套件（包含雙軌、英數短字與連續長句迴歸測試）

### 常用開發與部署指令（需經使用者授權後執行）

```bash
# 1. 執行完整單元測試（修改程式碼後必跑）
xcodebuild test -project gg.xcodeproj -scheme gg -destination 'platform=macOS' -quiet

# 2. 本機即時編譯與熱重載輸入法
./dev_reload.sh

# 3. 重新編譯並打包官方標準安裝套件 (gg.pkg)
./build_pkg.command

# 4. 單獨重新生成字典檔（若有修改 Source/Data/ 下的檔案）
cd Source/Data
make all           # 生成 data.txt, data-plain-bpmf.txt, associated-phrases-v2.txt
make sort          # 使用 LC_ALL=C 進行二進位排序（極重要，確保二分搜尋正確）
make check         # 驗證字典資料完整性
