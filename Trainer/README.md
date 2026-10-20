# KyonLM v2 整句字級語言模型訓練器 (`gg_trainer`)

本專案為 `gg` 注音輸入法的獨立神經語言模型訓練與匯出工具，完全依照【Kyon 新模型訓練規格 v1/v2】設計與實作。

## 一、架構與規格總覽

- **模型類型**：字級、單向（由左到右 Causal）Transformer Decoder-Only 語言模型（[`KyonCausalLM`](model.py)）
- **模型規模**：10 層、隱藏維度 `640`、注意力頭數 `10`、FFN 維度 `2560`、Pre-LayerNorm、輸入與輸出 Token Embedding 權重共享（約 **55.9M** 參數，Float16 約 **112 MB**）
- **詞表 (`data/vocab.txt`)**：`10,500` tokens，第 `0..3` 行固定為 `[PAD]`、`[UNK]`、`[BOS]`、`[EOS]`，涵蓋常用台灣繁體字、注音符號、全形標點與可列印 ASCII
- **Core ML 輸入與輸出規格（固定靜態形狀，支援 Apple Neural Engine）**：
  - 輸入 `input_ids`：`Int32 [8, 48]`（`[BOS] 字...` 後補 `[PAD]`）
  - 輸入 `target_ids`：`Int32 [8, 48]`（`input_ids` 左移一位，`[EOS]` 結尾，`PAD` 位置填 `0`）
  - 輸入 `attention_mask`：`Float16 [8, 48]`（有效目標位置為 `1.0`，`PAD` 位置為 `0.0`）
  - 輸出 `token_logprob`：`Float16 [8, 48]`（每個位置目標字的 $\log P(y_t \mid x_{\le t}) \times \text{mask}_t$，不輸出整個詞表的 logits）
- **Core ML Metadata**：
  - `kyon.version = 2.0.0`
  - `kyon.seq_len = 48`
  - `kyon.batch = 8`
  - `kyon.vocab_sha256 = <vocab.txt SHA-256>`

## 二、訓練方法（聯合交叉熵 + 動態同音對比排序損失）

1. **無洩漏純字元輸入**：移除舊版訓練器中會造成標籤洩漏（Label Leakage）的輔助訊號與雜湊快取，模型僅接收字元 ID。
2. **動態同音負樣本抽樣（[`HomophoneSampler`](dataset.py)）**：直接索引 `/Users/kevin/development/gg/Source/Data/data.txt` 中超過 22,000 組同音字詞群組與高頻易混同音對（如 `不在/不再`、`慢慢地/慢慢的`、`戴著/帶著`、`偵測/政策`、`冗餘/茸於`、`測試/策試`、`國家/果家`、`蘋果汁/蘋國汁`、`反應/反映`、`紀錄/記錄` 等），每個 Epoch 動態在線替換同音字產生難負樣本。
3. **測試集嚴格隔離**：[`prepare_corpus.py`](prepare_corpus.py) 自動讀取 `McBopomofoTests/Fixtures/homophone_regression.tsv` 並將測試集句子自訓練與驗證語料中完全剔除。

## 三、一鍵隔夜訓練與部署（9～10 小時）

```bash
cd /Users/kevin/development/gg_trainer
./run_train.sh
```

- 預設啟用 `caffeinate -i` 防止 Mac 休眠，並預設執行 **9.5 小時**（可透過 `./run_train.sh --hours 10` 調整時數）。
- 支援隨時按 `Ctrl+C` 安全中斷：收到中斷訊號後會自動載入最佳驗證分數的權重 (`checkpoints/best.pt`)，轉出 `KyonLM.mlpackage` 與 `KyonLM.mlmodelc`，並自動部署至：
  - `/Users/kevin/development/gg/Source/Resources/Model/`
  - `~/Library/Application Support/gg/Models/`
- 若有額外自備的台灣繁體中文語料（`.txt`），可直接放入 `corpus/raw/` 資料夾後執行 `./run_train.sh --rebuild-data`。
