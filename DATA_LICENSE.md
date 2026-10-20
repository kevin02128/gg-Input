# 資料與語料授權聲明 (Data and Corpus License)

**gg 輸入法** 與內建之 **KyonLM 神經語言模型** 所使用之訓練語料與辭典資料，衍生或整合自多個公眾開放授權來源，遵守各授權條款規範：

## 1. 訓練語料來源與開放授權

- **維基百科繁體中文（zh-tw / 台灣主題條目）**
  - 授權條款：[Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)](https://creativecommons.org/licenses/by-sa/4.0/)
  - 用途：因果語言模型之繁體中文語境脈絡與現代生活用語學習。

- **中華民國教育部國語辭典公眾開放資料**
  - 授權條款：[政府資料開放授權條款 (Open Government Data License, Version 1.0)](https://data.gov.tw/license)
  - 來源機關：中華民國教育部
  - 用途：基礎詞庫頻率統計、注音符號多音字標記與詞性對齊。

- **國家教育研究院台灣國語文公開語料庫摘要**
  - 授權條款：學術研究與教育推廣開放範圍
  - 用途：同音字混淆對（如在/再、的/得/地）語法搭配偏誤對比訓練。

## 2. 隱私與去識別化聲明

本專案在建立訓練語料時，已透過嚴格的正則過濾腳本（參見 [`Trainer/prepare_corpus.py`](Trainer/prepare_corpus.py)）進行資料清洗：
- 完全剔除任何包含電子郵件、電話號碼、身分證字號、私人地址與真實個人機敏資訊之語料。
- 絕無任何私人鍵擊記錄或使用者個人隱私數據參與模型訓練。
