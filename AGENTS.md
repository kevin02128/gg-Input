# AGENTS.md

本文件為 AI 編程助手（如 Antigravity / Copilot）在 `gg` 輸入法專案中工作的最高指導原則。

---

## 🚨 最高執行鐵律 (Strict Execution Policy - MUST FOLLOW)

1. **禁止未經允許修改或執行 (Plan-First Gate)**：
   - 當使用者提出新需求、Bug 修復、按鍵調整或架構詢問時，**絕對禁止**直接修改任何程式碼或資料檔，也**絕對禁止**未經授權直接執行 `./dev_reload.sh`、`./package_dmg.command`、`git commit` 或 `git push`。
2. **強制兩階段工作流 (Two-Phase Workflow)**：
   - **第一階段（唯讀掃描與提案）**：僅允許讀取檔案與搜尋程式碼。找出問題根因（Root Cause）後，必須使用**繁體中文**向使用者輸出結構化的【技術修改計畫書】（包含：根因分析、預計修改檔案、邊界條件防呆、預計新增的單元測試）。最後必須停下來詢問：「請確認以上計畫是否無誤，確認後我再開始實作。」
   - **第二階段（授權後實作）**：只有在收到使用者明確回覆「好」、「可以」、「開始執行」等同意字眼後，才允許修改檔案、執行 `xcodebuild test`、`./dev_reload.sh` 與 `./package_dmg.command`。

---

## Project Overview

`gg` 輸入法是基於 McBopomofo（小麥注音）深度改造的 macOS 繁體中文大千注音與中英雙軌智慧輸入法。
除支援傳統注音外，核心特色包含：
1. **中英雙軌並行預測 (`WTFMixedInputManager`)**：同時考量英文與注音合法性，支援 `Tab` 補全英文、聲調鍵觸發中文、注音語法相衝時自動鎖定純英文模式，以及科技英數短字（如 `4K`, `3D`, `5G`, `8K`, `M1`, `B2B`）直出。
2. **直覺化按鍵與標點邏輯**：按住 `Option ⌥` 強制 100% 輸出美式半形數字與符號（阻斷 macOS 原生冷門歐文符號如 `÷`, `æ`）。
3. **KyonLM 模型與輕量版雙軌打包**：支援完整版 (`gg.dmg`) 與純詞典輕量版 (`gg.lite.dmg`)。

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
xcodebuild test -project gg.xcodeproj -scheme gg -destination 'platform=macOS'

# 2. 本機即時編譯與熱重載輸入法
./dev_reload.sh

# 3. 重新打包簽署正式版 (gg.dmg) 與輕量版 (gg.lite.dmg)
./package_dmg.command

# 4. 單獨重新生成字典檔（若有修改 Source/Data/ 下的檔案）
cd Source/Data
make all           # 生成 data.txt, data-plain-bpmf.txt, associated-phrases-v2.txt
make sort          # 使用 LC_ALL=C 進行二進位排序（極重要，確保二分搜尋正確）
make check         # 驗證字典資料完整性
