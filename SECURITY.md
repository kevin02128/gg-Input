# 安全與隱私政策 (Security & Privacy Policy)

## 1. 百分之百本地離線運算承諾

**gg 輸入法 (gg Input Method)** 與內建之 **KyonLM 神經語言模型** 完全於使用者的 Mac 本機端（Apple Silicon CPU / GPU / Apple Neural Engine）閉環執行。

- **無遠端遙測**：本軟體不包含任何統計分析 SDK，亦不會向任何外部伺服器傳送使用者的鍵擊、輸入字詞或偏好設定。
- **無雲端推論**：所有上下文同音字校正、中英混打預測與詞頻調整，皆在本地記憶體與沙盒環境中完成。

## 2. 安全性漏洞通報流程

若您在本專案中發現潛在的安全性漏洞（如權限提升、記憶體越界或注入風險），請勿直接於公開的 GitHub Issues 中披露細節：

1. 請透過 GitHub Security Advisories 功能私下建立安全性通報（[Report a vulnerability](https://github.com/kevin02128/gg-Input/security/advisories/new)）。
2. 專案維護者將於收到通報後儘速確認並發布修補版本。
