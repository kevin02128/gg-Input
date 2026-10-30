import os
import sys
import io
import json
import warnings
warnings.filterwarnings("ignore", category=FutureWarning)
import torch
from transformers import AutoTokenizer

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..")) if os.path.basename(SCRIPT_DIR) in ("scripts", "src") else SCRIPT_DIR
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

try:
    from src.model import DualTaskCSCModel
except ImportError:
    from model import DualTaskCSCModel

MODEL_DIR = os.path.join(ROOT_DIR, "saved_model") if os.path.exists(os.path.join(ROOT_DIR, "saved_model")) else "ckiplab/bert-base-chinese"
BPMF_PATH = os.path.join(ROOT_DIR, "data", "char_to_bpmf.json")

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
    # Canonical Taiwanese Mandarin fuzzy syllable normalization
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

class IMEInferenceEngine:
    def __init__(self, model_path=MODEL_DIR):
        if torch.cuda.is_available():
            self.device = torch.device("cuda")
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            self.device = torch.device("mps")
        else:
            self.device = torch.device("cpu")
        print(f"[INFO] Loading model from: {model_path} (Device: {self.device})")
        self.tokenizer = AutoTokenizer.from_pretrained(model_path)
        self.model = DualTaskCSCModel.from_pretrained(model_path)
        self.model.to(self.device)
        self.model.eval()

        self.char_to_bpmf = {}
        # Prefer noise_engine_meta.json if it has fuller coverage, or merge both
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
                            # Prefer entry with heteronym list (len >= 3)
                            if k not in self.char_to_bpmf or (len(v) >= 3 and len(self.char_to_bpmf[k]) < 3):
                                self.char_to_bpmf[k] = v
                except Exception as e:
                    print(f"[WARN] Failed to load bpmf from {candidate_path}: {e}")

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
            return_tensors="pt",
            return_offsets_mapping=True,
            truncation=True,
            max_length=128
        )
        offset_mapping = enc.pop("offset_mapping")[0].tolist()
        input_ids = enc["input_ids"].to(self.device)
        attention_mask = enc["attention_mask"].to(self.device)
        token_type_ids = enc["token_type_ids"].to(self.device)

        with torch.no_grad():
            outputs = self.model(
                input_ids=input_ids,
                attention_mask=attention_mask,
                token_type_ids=token_type_ids,
            )
            det_logits = outputs["detection_logits"][0]
            cor_logits = outputs["correction_logits"][0]

            det_probs = torch.softmax(det_logits, dim=-1)
            cor_probs = torch.softmax(cor_logits, dim=-1)

        candidate_edits = {}
        valid_positions = []

        # Step 1: Compute candidate edits via Linear Bayesian Advantage Formula (S_i)
        for token_idx, (start, end) in enumerate(offset_mapping):
            if start == end or end - start != 1:
                continue
            orig_char = text[start]
            if not ("\u4e00" <= orig_char <= "\u9fff"):
                continue

            orig_id = input_ids[0, token_idx].item()
            if orig_id == self.tokenizer.unk_token_id:
                continue

            valid_positions.append((token_idx, start, orig_char, orig_id))

            p_orig = cor_probs[token_idx, orig_id].item()
            p_det = det_probs[token_idx, 1].item()

            top5 = torch.topk(cor_probs[token_idx], 5)
            best_cand, best_s, best_weight, best_conf = None, -999.0, 0.0, 0.0

            for cand_id_t, prob_cand_t in zip(top5.indices, top5.values):
                cand_id = cand_id_t.item()
                if cand_id == orig_id:
                    continue
                cand_char = self.tokenizer.decode([cand_id]).strip()
                if len(cand_char) != 1 or not ("\u4e00" <= cand_char <= "\u9fff"):
                    continue

                # Standard variant character protection (台/臺)
                if orig_char in ("台", "臺") and cand_char in ("台", "臺"):
                    continue

                is_phonetic, p_weight = self.get_phonetic_relation(orig_char, cand_char)
                p_cand = prob_cand_t.item()
                # S_i formula: P_cor(c_new) - P_cor(c_orig) + 0.5 * P_det
                s_score = p_cand - p_orig + 0.5 * p_det

                # Standard phonetic gatekeeper
                if is_phonetic and s_score > threshold_s:
                    if s_score > best_s:
                        best_s = s_score
                        best_cand = cand_char
                        best_weight = p_weight
                        best_conf = p_cand
                # Pure neural extreme confidence fallback (for unmapped characters or extreme phonetic variants)
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
                    "top3": [(self.tokenizer.decode([idx.item()]).strip(), round(prob.item(), 4)) for idx, prob in zip(top5.indices[:3], top5.values[:3])],
                }

        # Step 2: Symmetric Neighbor Wake-up
        # When position i triggers an edit, examine neighbors j in {i-1, i+1}
        token_to_pos = {t: (s, c, oid) for t, s, c, oid in valid_positions}
        for confirmed_pos in list(candidate_edits.keys()):
            confirmed_token = candidate_edits[confirmed_pos]["token_idx"]
            for neighbor_token in (confirmed_token - 1, confirmed_token + 1):
                if neighbor_token not in token_to_pos:
                    continue
                n_pos, n_char, n_oid = token_to_pos[neighbor_token]
                if n_pos in candidate_edits:
                    continue

                p_n_orig = cor_probs[neighbor_token, n_oid].item()
                p_n_det = det_probs[neighbor_token, 1].item()
                n_top5 = torch.topk(cor_probs[neighbor_token], 5)

                for cand_id_t, prob_cand_t in zip(n_top5.indices, n_top5.values):
                    cand_id = cand_id_t.item()
                    if cand_id == n_oid:
                        continue
                    cand_char = self.tokenizer.decode([cand_id]).strip()
                    if len(cand_char) != 1 or not ("\u4e00" <= cand_char <= "\u9fff"):
                        continue
                    if n_char in ("台", "臺") and cand_char in ("台", "臺"):
                        continue

                    is_phonetic, p_weight = self.get_phonetic_relation(n_char, cand_char)
                    p_cand = prob_cand_t.item()

                    # Wake-up condition: phonetically related and candidate prob > orig prob
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
                            "top3": [(self.tokenizer.decode([idx.item()]).strip(), round(prob.item(), 4)) for idx, prob in zip(n_top5.indices[:3], n_top5.values[:3])],
                        }
                        break

        return list(candidate_edits.values())

    def correct(self, text, threshold_s=0.45):
        text = text.strip()
        if not text:
            return text, []

        edits = self._predict_once(text, threshold_s)
        if not edits:
            return text, []

        edits_by_pos = {e["pos"]: e for e in edits}
        sorted_pos = sorted(edits_by_pos.keys())

        # Check if there are consecutive character edits (Adjacent Competition)
        has_adjacent = any(sorted_pos[i + 1] - sorted_pos[i] == 1 for i in range(len(sorted_pos) - 1))

        if not has_adjacent:
            chars = list(text)
            for e in edits:
                chars[e["pos"]] = e["to"]
            return "".join(chars), edits

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
        pass2_edits = self._predict_once(intermediate_text, threshold_s)
        if pass2_edits:
            chars2 = list(intermediate_text)
            final_edits = list(selected_edits)
            for e in pass2_edits:
                chars2[e["pos"]] = e["to"]
                e["from"] = text[e["pos"]]
                final_edits.append(e)
            return "".join(chars2), final_edits

        return intermediate_text, selected_edits

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

    print("\n[Benchmark Tests (Pure Neural Zero-Patch)]")
    for text in test_cases:
        res, edits = engine.correct(text)
        print(f"Input:  {text}")
        print(f"Output: {res}")
        if edits:
            for e in edits:
                top3_str = ", ".join([f"{c}:{p:.2f}" for c, p in e.get("top3", [])])
                det_p = f"{e['det_prob'] * 100:.1f}%" if isinstance(e['det_prob'], float) else e['det_prob']
                cor_p = f"{e['cor_conf'] * 100:.1f}%" if isinstance(e['cor_conf'], float) else e['cor_conf']
                s_sc = f"{e['s_score']:.3f}" if isinstance(e.get('s_score'), float) else "N/A"
                print(f"  [{e['pos']}] {e['from']} -> {e['to']} (S: {s_sc}, det: {det_p}, conf: {cor_p}) | Top3: [{top3_str}]")
        else:
            print("  No modifications")
        print()

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Taiwan IME CSC 測試程式")
    parser.add_argument("--model-dir", default=MODEL_DIR, help="模型目錄路徑")
    parser.add_argument("--text", default=None, help="單句測試文字（提供時直接輸出結果並退出）")
    args = parser.parse_args()

    engine = IMEInferenceEngine(model_path=args.model_dir)
    if args.text:
        res, edits = engine.correct(args.text)
        print(f"原句: {args.text}")
        print(f"校正: {res}")
        if edits:
            for e in edits:
                conf = f"{e['cor_conf']:.2f}" if isinstance(e.get('cor_conf'), float) else e.get('cor_conf', '')
                print(f"  * 第 {e['pos']} 字: 「{e['from']}」->「{e['to']}」 (信心度: {conf})")
        else:
            print("  * 無需修改 (全句正確)")
        sys.exit(0)

    run_benchmark(engine)

    print("=" * 60)
    print("【互動打字測試模式】請輸入句子測試糾錯（輸入 q 或 exit 退出）：")
    print("=" * 60)
    try:
        while True:
            text = input("請輸入測試文字 > ").strip()
            if not text:
                continue
            if text.lower() in ["q", "exit", "quit"]:
                break
            res, edits = engine.correct(text)
            print(f"校正結果: {res}")
            if edits:
                for e in edits:
                    conf = f"{e['cor_conf']:.2f}" if isinstance(e.get('cor_conf'), float) else e.get('cor_conf', '')
                    print(f"  * 第 {e['pos']} 字: 「{e['from']}」->「{e['to']}」 (信心度: {conf})")
            else:
                print("  * 無需修改 (句子完全正確)")
            print()
    except (EOFError, KeyboardInterrupt):
        pass

