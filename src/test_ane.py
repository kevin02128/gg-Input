import os
import sys
import io
import json
import time
import warnings
warnings.filterwarnings("ignore")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..")) if os.path.basename(SCRIPT_DIR) in ("scripts", "src") else SCRIPT_DIR
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

COREML_PATH = os.path.join(ROOT_DIR, "ml.mlpackage")
TOKENIZER_DIR = os.path.join(ROOT_DIR, "saved_model") if os.path.exists(os.path.join(ROOT_DIR, "saved_model")) else "ckiplab/bert-base-chinese"
BPMF_PATH = os.path.join(ROOT_DIR, "data", "char_to_bpmf.json")
MAX_SEQ_LEN = 128

FUZZY_PAIRS = [
    ('ㄓ', 'ㄗ'), ('ㄗ', 'ㄓ'),
    ('ㄔ', 'ㄘ'), ('ㄘ', 'ㄔ'),
    ('ㄕ', 'ㄙ'), ('ㄙ', 'ㄕ'),
    ('ㄢ', 'ㄤ'), ('ㄤ', 'ㄢ'),
    ('ㄣ', 'ㄥ'), ('ㄥ', 'ㄣ'),
    ('ㄏㄨ', 'ㄈ'), ('ㄈ', 'ㄏㄨ'),
    ('ㄈ', 'ㄏ'), ('ㄏ', 'ㄈ'),
    ('ㄌ', 'ㄖ'), ('ㄖ', 'ㄌ')
]

def normalize_bpmf(bpmf_clean):
    s = bpmf_clean
    s = s.replace('ㄏㄨ', 'ㄈ')
    for f1, f2 in [
        ('ㄓ', 'ㄗ'),
        ('ㄔ', 'ㄘ'),
        ('ㄕ', 'ㄙ'),
        ('ㄤ', 'ㄢ'),
        ('ㄥ', 'ㄣ'),
        ('ㄈ', 'ㄏ'),
        ('ㄖ', 'ㄌ'),
    ]:
        s = s.replace(f1, f2)
    return s

def _iter_readings(entry):
    if not entry:
        return
    yield entry[0], entry[1]
    if len(entry) >= 3 and isinstance(entry[2], list):
        for pair in entry[2]:
            if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                yield pair[0], pair[1]

class ANEInferenceEngine:
    def __init__(self, coreml_path=COREML_PATH, tokenizer_path=TOKENIZER_DIR):
        if not os.path.exists(coreml_path):
            print(f"[ERROR] 找不到 CoreML 模型: {coreml_path}")
            print("請先執行轉換指令: python3 convert_coreml.py (或 python3 scripts/convert_coreml.py)")
            sys.exit(1)

        try:
            import coremltools as ct
        except ImportError:
            print("[ERROR] 尚未安裝 coremltools。請先執行: pip install coremltools")
            sys.exit(1)

        from transformers import AutoTokenizer
        import numpy as np
        self.np = np

        print("=" * 65)
        print(f"[INFO] 正在載入 Apple Neural Engine 原生模型: {os.path.basename(coreml_path)}")
        t0 = time.perf_counter()
        self.model = ct.models.MLModel(coreml_path)
        print(f"[INFO] ANE 模型載入完成 (耗時: {(time.perf_counter() - t0) * 1000:.1f} ms)")

        print(f"[INFO] 正在載入 Tokenizer: {tokenizer_path}")
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)

        self.char_to_bpmf = {}
        for candidate_path in (
            os.path.join(ROOT_DIR, "data", "noise_engine_meta.json"),
            BPMF_PATH,
        ):
            if os.path.exists(candidate_path):
                try:
                    with open(candidate_path, "r", encoding="utf-8") as f:
                        d = json.load(f)
                        table = d.get("char_to_bpmf", d)
                        for k, v in table.items():
                            if k not in self.char_to_bpmf or (len(v) >= 3 and len(self.char_to_bpmf[k]) < 3):
                                self.char_to_bpmf[k] = v
                except Exception as e:
                    print(f"[WARN] Failed to load bpmf from {candidate_path}: {e}")

        # Warmup ANE
        dummy_ids = self.np.zeros((1, MAX_SEQ_LEN), dtype=self.np.int32)
        dummy_mask = self.np.ones((1, MAX_SEQ_LEN), dtype=self.np.int32)
        _ = self.model.predict({"input_ids": dummy_ids, "attention_mask": dummy_mask})
        print("[INFO] ANE 晶片預熱完成，處於極速待命狀態！")
        print("=" * 65)

    def get_phonetic_relation(self, c1, c2):
        if c1 == c2:
            return False, 0.0
        b1 = self.char_to_bpmf.get(c1)
        b2 = self.char_to_bpmf.get(c2)
        if not b1 or not b2:
            return False, 0.0

        best_weight = 0.0
        for full1, clean1 in _iter_readings(b1):
            norm1 = normalize_bpmf(clean1)
            for full2, clean2 in _iter_readings(b2):
                if full1 == full2:
                    return True, 1.0
                if clean1 == clean2 and best_weight < 0.6:
                    best_weight = 0.6
                elif norm1 == normalize_bpmf(clean2) and best_weight < 0.4:
                    best_weight = 0.4

        if best_weight > 0.0:
            return True, best_weight
        return False, 0.0

    def _predict_once(self, text, threshold_s=0.45):
        enc = self.tokenizer(
            text,
            return_offsets_mapping=True,
            truncation=True,
            max_length=MAX_SEQ_LEN,
            padding="max_length",
        )
        offset_mapping = enc["offset_mapping"]
        input_ids = self.np.array([enc["input_ids"]], dtype=self.np.int32)
        attention_mask = self.np.array([enc["attention_mask"]], dtype=self.np.int32)

        # Pure hardware inference on Apple Neural Engine
        t0 = time.perf_counter()
        preds = self.model.predict({"input_ids": input_ids, "attention_mask": attention_mask})
        latency_ms = (time.perf_counter() - t0) * 1000

        det_probs = preds["detection_probs"][0]  # shape: [seq_len, 2]
        cor_probs = preds["correction_probs"][0]  # shape: [seq_len, vocab_size]

        candidate_edits = {}
        valid_positions = []

        # Step 1: Compute candidate edits via Linear Bayesian Advantage Formula (S_i)
        for token_idx, (start, end) in enumerate(offset_mapping):
            if start == end or end - start != 1:
                continue
            if start >= len(text):
                continue
            orig_char = text[start]
            if not ("\u4e00" <= orig_char <= "\u9fff"):
                continue

            orig_id = int(input_ids[0, token_idx])
            if orig_id == self.tokenizer.unk_token_id:
                continue

            valid_positions.append((token_idx, start, orig_char, orig_id))

            p_orig = float(cor_probs[token_idx, orig_id])
            p_det = float(det_probs[token_idx, 1])

            # Find top-5 candidate tokens
            top5_indices = self.np.argsort(cor_probs[token_idx])[-5:][::-1]

            best_cand, best_s, best_weight, best_conf = None, -999.0, 0.0, 0.0

            for cand_id_np in top5_indices:
                cand_id = int(cand_id_np)
                if cand_id == orig_id:
                    continue
                cand_char = self.tokenizer.decode([cand_id]).strip()
                if len(cand_char) != 1 or not ("\u4e00" <= cand_char <= "\u9fff"):
                    continue
                if orig_char in ("台", "臺") and cand_char in ("台", "臺"):
                    continue

                is_phonetic, p_weight = self.get_phonetic_relation(orig_char, cand_char)
                p_cand = float(cor_probs[token_idx, cand_id])
                s_score = p_cand - p_orig + 0.5 * p_det

                # Standard phonetic gatekeeper
                if is_phonetic and s_score > threshold_s:
                    if s_score > best_s:
                        best_s = s_score
                        best_cand = cand_char
                        best_weight = p_weight
                        best_conf = p_cand
                # Pure neural extreme confidence fallback
                elif not is_phonetic and p_det > 0.60 and s_score > 1.10:
                    if s_score > best_s:
                        best_s = s_score
                        best_cand = cand_char
                        best_weight = 0.5
                        best_conf = p_cand

            if best_cand:
                candidate_edits[start] = {
                    "pos": start,
                    "token_idx": token_idx,
                    "from": orig_char,
                    "to": best_cand,
                    "s_score": best_s,
                    "p_weight": best_weight,
                    "det_prob": p_det,
                    "cor_conf": best_conf,
                    "p_orig": p_orig,
                    "top3": [
                        (self.tokenizer.decode([int(idx)]).strip(), round(float(cor_probs[token_idx, int(idx)]), 4))
                        for idx in top5_indices[:3]
                    ],
                }

        # Step 2: Symmetric Neighbor Wake-up
        token_to_pos = {t: (s, c, oid) for t, s, c, oid in valid_positions}
        for confirmed_pos in list(candidate_edits.keys()):
            confirmed_token = candidate_edits[confirmed_pos]["token_idx"]
            for neighbor_token in (confirmed_token - 1, confirmed_token + 1):
                if neighbor_token not in token_to_pos:
                    continue
                n_pos, n_char, n_oid = token_to_pos[neighbor_token]
                if n_pos in candidate_edits:
                    continue

                p_n_orig = float(cor_probs[neighbor_token, n_oid])
                p_n_det = float(det_probs[neighbor_token, 1])
                n_top5_indices = self.np.argsort(cor_probs[neighbor_token])[-5:][::-1]

                for cand_id_np in n_top5_indices:
                    cand_id = int(cand_id_np)
                    if cand_id == n_oid:
                        continue
                    cand_char = self.tokenizer.decode([cand_id]).strip()
                    if len(cand_char) != 1 or not ("\u4e00" <= cand_char <= "\u9fff"):
                        continue
                    if n_char in ("台", "臺") and cand_char in ("台", "臺"):
                        continue

                    is_phonetic, p_weight = self.get_phonetic_relation(n_char, cand_char)
                    p_cand = float(cor_probs[neighbor_token, cand_id])

                    if is_phonetic and p_cand > p_n_orig:
                        s_score = p_cand - p_n_orig + 0.5 * p_n_det
                        candidate_edits[n_pos] = {
                            "pos": n_pos,
                            "token_idx": neighbor_token,
                            "from": n_char,
                            "to": cand_char,
                            "s_score": s_score,
                            "p_weight": p_weight,
                            "det_prob": p_n_det,
                            "cor_conf": p_cand,
                            "p_orig": p_n_orig,
                            "top3": [
                                (self.tokenizer.decode([int(idx)]).strip(), round(float(cor_probs[neighbor_token, int(idx)]), 4))
                                for idx in n_top5_indices[:3]
                            ],
                        }
                        break

        return list(candidate_edits.values()), latency_ms

    def correct(self, text, threshold_s=0.45):
        text = text.strip()
        if not text:
            return text, [], 0.0

        edits, latency_ms = self._predict_once(text, threshold_s)
        if not edits:
            return text, [], latency_ms

        edits_by_pos = {e["pos"]: e for e in edits}
        sorted_pos = sorted(edits_by_pos.keys())

        # Check if there are consecutive character edits (Adjacent Competition)
        has_adjacent = any(sorted_pos[i + 1] - sorted_pos[i] == 1 for i in range(len(sorted_pos) - 1))

        if not has_adjacent:
            chars = list(text)
            for e in edits:
                chars[e["pos"]] = e["to"]
            return "".join(chars), edits, latency_ms

        # Adjacent arbitration: prioritize highest phonetic weight (1.0 > 0.6 > 0.5 > 0.4), then highest s_score
        selected_edits = []
        i = 0
        while i < len(sorted_pos):
            cluster = [sorted_pos[i]]
            while i + 1 < len(sorted_pos) and sorted_pos[i + 1] - sorted_pos[i] == 1:
                i += 1
                cluster.append(sorted_pos[i])
            best_pos = max(cluster, key=lambda p: (edits_by_pos[p]["p_weight"], edits_by_pos[p]["s_score"]))
            selected_edits.append(edits_by_pos[best_pos])
            i += 1

        chars = list(text)
        for e in selected_edits:
            chars[e["pos"]] = e["to"]
        intermediate_text = "".join(chars)

        # Conditional Pass 2 verification
        pass2_edits, pass2_lat = self._predict_once(intermediate_text, threshold_s)
        total_latency_ms = latency_ms + pass2_lat
        if pass2_edits:
            chars2 = list(intermediate_text)
            final_edits = list(selected_edits)
            for e in pass2_edits:
                chars2[e["pos"]] = e["to"]
                e["from"] = text[e["pos"]]
                final_edits.append(e)
            return "".join(chars2), final_edits, total_latency_ms

        return intermediate_text, selected_edits, total_latency_ms


def run_benchmark(engine):
    test_cases = [
        "我要穿語衣",
        "你要癡飯嗎",
        "幫我戴一把雨傘",
        "不要一直拿輸本",
        "他在次打電話向主管報告進度",
        "我因該明天會去台北開會",
        "這份 report 請在下週一前 check 完畢",
        "我們約在台北 101 大樓 Meet，你因該知道地點吧",
    ]

    print("\n[Benchmark Tests (Apple Neural Engine 原生推論)]")
    latencies = []
    for text in test_cases:
        res, edits, lat = engine.correct(text)
        latencies.append(lat)
        print(f"Input:   {text}")
        print(f"Output:  {res}  (ANE: {lat:.2f} ms)")
        if edits:
            for e in edits:
                det_p = f"{e['det_prob'] * 100:.1f}%"
                cor_p = f"{e['cor_conf'] * 100:.1f}%"
                print(f"  [{e['pos']}] {e['from']} -> {e['to']} (S: {e['s_score']:.3f}, det: {det_p}, conf: {cor_p})")
        else:
            print("  No modifications")
        print()

    print(f"[SUCCESS] 基準測試完成！ANE 平均單句推論耗時: {sum(latencies)/len(latencies):.2f} ms ⚡")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Mac ANE IME CSC 測試程式")
    parser.add_argument("--text", default=None, help="單句測試文字（提供時直接輸出結果並退出）")
    args = parser.parse_args()

    engine = ANEInferenceEngine()
    if args.text:
        res, edits, lat = engine.correct(args.text)
        print(f"原句: {args.text}")
        print(f"校正: {res}  (ANE 硬體耗時: {lat:.2f} ms ⚡)")
        if edits:
            for e in edits:
                print(f"  * 第 {e['pos']} 字: 「{e['from']}」->「{e['to']}」 (置信度: {e['cor_conf']*100:.1f}%)")
        else:
            print("  * 無需修改 (句子完全正確)")
        sys.exit(0)

    run_benchmark(engine)

    print("=" * 65)
    print("【Mac ANE 原生神經網絡即時打字測試】（輸入 q 或 exit 退出）：")
    print("=" * 65)
    try:
        while True:
            text = input("請輸入測試文字 > ").strip()
            if not text:
                continue
            if text.lower() in ["q", "exit", "quit"]:
                break
            res, edits, lat = engine.correct(text)
            print(f"校正結果: {res}  (ANE 硬體耗時: {lat:.2f} ms ⚡)")
            if edits:
                for e in edits:
                    print(f"  * 第 {e['pos']} 字: 「{e['from']}」->「{e['to']}」 (置信度: {e['cor_conf']*100:.1f}%)")
            else:
                print("  * 無需修改 (句子完全正確)")
            print()
    except (EOFError, KeyboardInterrupt):
        pass


if __name__ == "__main__":
    main()
