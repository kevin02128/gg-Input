# Model Card: gg Neural Candidate Reranker (`ggInference`)

- **模型名稱**：`gg-bert-csc-reranker-v1`（部署檔名：`ml.mlpackage` / `ml.mlmodelc`）
- **版本**：`1.0.0`（2026-10-29）
- **任務類型**：繁體中文注音輸入法「組字區同讀音候選字重排（Soft Boost）」之錯字偵測與修正機率推論（Dual-Task Chinese Spelling Check: Detection + Correction）
- **底座模型**：中央研究院詞庫小組 `ckiplab/bert-base-chinese`（12 層 Transformer Encoder, Hidden Size 768, Attention Heads 12, Vocab Size 21,128）
- **整體發布授權**：**GNU General Public License v3.0 (GPL-3.0)**（依循底座模型 `ckiplab/bert-base-chinese` 之 GPL-3.0 授權要求）

---

## 1. 模型規格與資產雜湊（SHA-256）

- **推論格式**：Apple CoreML `.mlpackage` / `.mlmodelc`（FP16 半精度，目標運算單元：`.all` 含 Apple Neural Engine）
- **輸入規格**：
  - `input_ids`：`Int32[1, 128]`（固定長度 128，含 `[CLS]=101`、`[SEP]=102`，不足補 `[PAD]=0`）
  - `attention_mask`：`Int32[1, 128]`（有效位置為 `1`，Padding 位置為 `0`）
- **輸出規格**：
  - `detection_probs`：`Float16/Float32[1, 128, 2]`（各位置經 Softmax 後之 `[P(正確), P(錯字)]`）
  - `correction_probs`：`Float16/Float32[1, 128, 21128]`（各位置經 Softmax 後對 21,128 詞表之機率分布）
- **資產校验雜湊（SHA-256）**：
  - `ml.mlpackage/Data/com.apple.CoreML/weights/weight.bin`：`0434607696f23224761f810ec3c5d6cf5f516782a6b657daebf339c4db5e03be`
  - `ml.mlpackage/Data/com.apple.CoreML/model.mlmodel`：`7a8bbb5a8479e9c162e41e3d5e1edcedb91568b51fdac65ea8cde1f306c69c89`
  - `saved_model/vocab.txt`：`45bbac6b341c319adc98a532532882e91a9cefc0329aa57bac9ae761c27b291c`

---

## 2. 預期用途與嚴格邊界（Intended Use & Out-of-Scope）

### 預期用途
本模型專供 macOS `gg` 輸入法於本機離線環境（內嵌於沙盒化之 `ggInference.xpc` 服務）執行：
1. 當使用者於組字區停頓達 300 ms 時，讀取目前組字區內之 Viterbi 首選句與各位置「同讀音（相同注音讀音）」之字典候選詞。
2. 於 `ggInference.xpc` 內完成推論與候選詞對應位置之 log 機率提取，僅將小型純量陣列回傳主程序。
3. 若該位置錯字偵測機率 $\text{det\_prob} \ge \tau_{\text{det}}$ 且同音最佳候選相對於目前首選之平均 log 機率優勢 $\ge \tau_{\text{adv}}$，則對該候選節點施加不超過上限 $B$（且嚴格低於 `OverridingScore = 42.0`）之一次性軟加分（Soft Boost），重新求解一次 Viterbi 網格。

### 明確禁止與不做事項
- **不修改已送出文字**：絕不干預已按 Enter 鍵送出至宿主應用程式之文字，亦不繪製任何波浪底線。
- **不覆蓋使用者記憶**：凡存在於 `UserOverrideModel` 之詞彙、本次組字中使用者手動選過之候選詞、或本工作階段內曾被使用者改選／退格拒絕之推薦詞，模型一律讓路、不加分。
- **不持久化模型結果**：模型軟加分僅作用於當次組字網格，絕不寫入 `UserOverrideModel`。
- **不連網、不記錄**：XPC 服務受 App Sandbox 強制隔離，無 `com.apple.security.network.client` 權限，不讀寫使用者磁碟檔案，組字內容絕不寫入任何系統日誌。

---

## 3. 訓練資料、授權與可重現計數紀錄

### 3.1 資料來源與授權表

| 資料集名稱 | 原始有效句數 | 授權條款／法規依據 | 前處理與去識別化說明 |
| :--- | ---: | :--- | :--- |
| **台灣主權語料庫**（Taiwan Sovereign Corpus） | 2,826,104 | 《政府資料開放授權條款－第 1 版》（OGDL-Taiwan-1.0）；司法院裁判書正文依《著作權法》第 9 條第 1 項第 1 款屬公共領域 | 涵蓋政府開放資料、公報、司法院公開裁判書；已遮蔽姓名、案號與身分證字號，正規化 CJK 相容字元並過濾長度 8～120 字 |
| **國教院臺灣華語文語料庫**（NAER COCT） | 302,410 | 《政府資料開放授權條款－第 1 版》（OGDL-Taiwan-1.0） | 原始 Parquet 共 310,916 列，經繁體化（OpenCC `s2twp`）與句長 8～120 字、至少 6 個漢字過濾後得 302,410 句 |
| **社群日常對話語料**（PTT／Dcard 公開短句） | 112,732（原始檔）<br>111,092（跨庫淨新增） | 公開網路文本，無明確開放授權條款 | 已去除帳號 ID、時間戳記與 URL；僅存在於已微調之模型權重中，原始文本不隨軟體散佈 |

### 3.2 社群語料句數差異之可重現核對紀錄（`112,732` vs `111,092` vs `112,533`）

針對歷次紀錄中出現之三個社群語料句數，依 `src/prepare_dataset.py`（隨機種子 `random.seed(42)`）實際執行邏輯與產物核對如下：

1. **原始獨立句數 `112,732` 句**：
   - `data/raw/chat_clean.jsonl` 內符合句長 4～120 字且至少含 3 個漢字之唯一句總數為 **112,732 句**（即 `len(chat_set) = 112,732`）。
2. **跨庫去重後淨新增句數 `111,092` 句**：
   - 靜態基底庫（台灣主權語料庫 2,826,104 句 + 國教院 COCT 302,410 句）內部去重後共 **3,128,488 句**（`base_sentences`）。
   - 將 `base_sentences`（3,128,488 句）與 `chat_sentences`（112,732 句）合併執行跨庫去重 `list(dict.fromkeys(base_sentences + chat_sentences))` 後，總唯一池 `unique_pool` 為 **3,239,580 句**。
   - 因其中有 **1,640 句**日常短句同時出現於靜態基底庫與社群語料中（`3,128,488 + 112,732 - 3,239,580 = 1,640`），故社群語料對總唯一池之「淨新增句數」為 `112,732 - 1,640 =` **111,092 句**。
3. **訓練集 2 倍加權抽樣句數 `112,533` 句**：
   - 自 `unique_pool`（3,239,580 句）切出末端 **14,000 句**作為獨立驗證集 `data/dev.jsonl`（其中含屬於 `chat_set` 之句子 199 句），剩餘訓練基底 `train_unique` 為 `3,239,580 - 14,000 =` **3,225,580 句**。
   - `src/prepare_dataset.py` 第 454 行以 `[t for t in train_unique if t in chat_set]` 進行 2 倍過採樣（Oversampling），由於 `train_unique` 中共有 `112,732 - 199 =` **112,533 句**屬於 `chat_set`（包含前述與靜態基底庫重疊之 1,640 句），故加權後訓練集總筆數為 `3,225,580 + 112,533 =` **3,338,113 句**（`data/train_clean.jsonl`）。

### 3.3 社群語料之著作權與平台條款風險揭露
- 去識別化處理僅解決個人資料保護問題，並未賦予公開網路文本明確之著作權再授權或豁免各該平台之服務條款限制。
- 該批語料已混合於現有微調權重中；本專案公開完整訓練腳本（`src/train.py`）與資料處理腳本（`src/prepare_dataset.py`），若未來合規政策要求移除社群語料，可直接以純 OGDL-Taiwan-1.0 語料（台灣主權語料庫 + 國教院 COCT 共 3,128,488 句）重新執行微調。

---

## 4. 訓練與轉換腳本重現方式

相關腳本位於模型工程儲存庫（`gg_model`）：
- 資料前處理與合成錯字腳本：`src/prepare_dataset.py`
- 雙任務微調訓練腳本：`src/train.py`（與 `src/model.py` 之 `DualTaskCSCModel`）
- CoreML FP16 轉換腳本：`scripts/convert_coreml.py`

---

## 5. 已知限制（Limitations）

1. **領域落差**：訓練語料以政府開放資料、裁判書與標準教材為主（佔比逾 96%），對於高度口語、網路新詞、中英數夾雜（如程式碼變數、科技專有名詞）之修正能力有限，因此必須搭配雙門檻（$\tau_{\text{det}}, \tau_{\text{adv}}$）與保守軟加分上限 $B$，且功能預設關閉。
2. **硬體與系統限制**：僅支援搭載 Apple Silicon（M 系列晶片）且運行 macOS 13.0 以上之設備；於 Intel Mac 或開啟 macOS「低電量模式」時自動停用。
3. **冷啟動延遲**：CoreML 模型首次編譯／載入至 ANE 約需 1～4 秒，故採「第一鍵背景非同步預熱」機制，預熱完成前之組字請求直接略過、絕不排隊阻塞打字。
