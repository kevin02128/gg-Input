# 參與貢獻指南 (Contributing to gg Input Method)

感謝您對 **gg 輸入法** 的關注與貢獻！本指南說明如何設定開發環境、提交程式碼修正與擴充台灣繁體中文詞庫。

## 1. 開發環境需求

- **硬體**：搭載 Apple Silicon (M1 / M2 / M3 / M4) 之 Mac
- **作業系統**：macOS 14.0 或更新版本（Runtime 支援 macOS 13.0+）
- **開發工具**：Xcode 16.0 或更新版本（支援 Swift Testing 框架）、Python 3.9+

## 2. 快速建置與熱重載工作流

1. 複製儲存庫：
   ```bash
   git clone https://github.com/kevin02128/gg-Input.git
   cd gg-Input
   ```
2. 首次建置前準備模型目錄（若尚未下載 `KyonLM.mlmodelc`）：
   ```bash
   ./scripts/setup_model.sh
   ```
3. 日常開發與秒級熱更新：
   ```bash
   ./dev_reload.sh
   ```
   此腳本會自動編譯 Debug 版本、替換 `~/Library/Input Methods/gg.app` 並重新啟動輸入法行程。
4. 執行單元測試：
   ```bash
   xcodebuild test -project gg.xcodeproj -scheme gg -destination "platform=macOS"
   ```

## 3. 提交規範 (Conventional Commits)

所有的 Git Commit 與 Pull Request 標題請遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

- `feat(scope): 新增功能說明`
- `fix(scope): 修復錯誤說明`
- `docs(scope): 文件更新`
- `refactor(scope): 程式碼重構`
- `test(scope): 新增或調整測試`

## 4. 語言與編碼守則

- 所有註解、文件與介面本地化請使用**繁體中文（台灣習慣用語）**或英文。
- 除詞庫資料表外，程式碼與技術文件中請勿使用表情符號。
