# Taiwan IME CKIP BERT Spelling Correction Model (Ready-to-Use)

本目錄存放已微調完成的繁體中文雙任務同音糾錯模型資產，專供未來離線文字校對、伺服器 API、其他文字處理外掛等**推論使用**。

---

## 目錄結構

```
gg_model/
├── saved_model/         # PyTorch BERT 權重與 Tokenizer (409 MB)
├── ml.mlpackage/        # Apple Silicon CoreML FP16 權重 (195 MB)
├── data/
│   └── char_to_bpmf.json # 注音同音字映射表 (過濾候選字用)
├── src/
│   ├── model.py         # DualTaskCSCModel PyTorch 結構定義
│   ├── test.py          # PyTorch 推論 / 糾錯測試指令 (CLI & 互動模式)
│   └── test_ane.py      # CoreML (Apple Neural Engine) 推論測試
├── scripts/
│   └── convert_coreml.py # 若修改 PyTorch 權重後重新導出 CoreML 的腳本
├── requirements.txt     # 使用本模型所需之 Python 套件
└── MODEL_CARD.md        # 模型架構、指標與開源授權聲明 (GPL-3.0)
```

---

## 權重檔下載 (Weights Download)

由於二進位權重檔較大（PyTorch + CoreML 共約 541 MB），不直接置於 Git 倉庫中。
請至 [Releases](https://github.com/kevin02128/gg-Input/releases) 下載 `gg-model-weights.zip`，並解壓縮至本目錄即可取得完整的 `saved_model/` 與 `ml.mlpackage/`。

---

## 如何使用此模型

### 1. 安裝環境
```bash
pip install -r requirements.txt
```

### 2. PyTorch 推論 (支援 GPU / MPS / CPU)
- **單句糾錯**：
  ```bash
  python src/test.py --text "我要穿語衣"
  ```
- **互動打字糾錯**：
  ```bash
  python src/test.py
  ```

### 3. Apple CoreML (Mac 原生極速推論，約 11 ms)
```bash
python src/test_ane.py --text "我要穿語衣"
```

### 4. 重新導出 CoreML
若未來修改了 PyTorch 權重或想重新轉換：
```bash
python scripts/convert_coreml.py
```
