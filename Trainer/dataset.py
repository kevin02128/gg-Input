#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KyonLM Dynamic Homophone Contrastive Dataset (dataset.py)

Encodes sentences into exact Core ML input format:
  - input_ids:      Int64/Int32 [48] ([BOS] c_1 ... c_L [PAD]...)
  - target_ids:     Int64/Int32 [48] (c_1 ... c_L [EOS] 0...)
  - attention_mask: Float32     [48] (1.0 on valid targets, 0.0 on PAD)

Dynamically generates same-reading homophone negative sentences on the fly
from Source/Data/data.txt (22,000+ reading groups) and curated high-frequency
confusable pairs, with zero label leakage.
"""

import os
import random
from typing import Dict, List, Optional, Tuple

import torch
from torch.utils.data import Dataset

PAD_ID = 0
UNK_ID = 1
BOS_ID = 2
EOS_ID = 3

PRIORITY_CONFUSABLES: Dict[str, List[str]] = {
    "不在": ["不再"],
    "不再": ["不在"],
    "先在": ["先再", "現在"],
    "現在": ["先在", "現再"],
    "正在": ["正再"],
    "在": ["再"],
    "再": ["在"],
    "慢慢地": ["慢慢的"],
    "認真地": ["認真的"],
    "仔細地": ["仔細的"],
    "努力地": ["努力的"],
    "悄悄地": ["悄悄的"],
    "靜靜地": ["靜靜的"],
    "漸漸地": ["漸漸的"],
    "迅速地": ["迅速的"],
    "徹底地": ["徹底的"],
    "積極地": ["積極的"],
    "持續地": ["持續的"],
    "順利地": ["順利的"],
    "成功地": ["成功的"],
    "清楚地": ["清楚的"],
    "詳細地": ["詳細的"],
    "溫暖的": ["溫暖地"],
    "詳細的": ["詳細地"],
    "完整的": ["完整地"],
    "穩定的": ["穩定地"],
    "地": ["的", "得"],
    "的": ["地", "得"],
    "得": ["的", "地"],
    "戴著": ["帶著"],
    "帶著": ["戴著"],
    "戴上": ["帶上"],
    "戴好": ["帶好"],
    "戴": ["帶"],
    "帶": ["戴"],
    "偵測": ["政策"],
    "政策": ["偵測"],
    "冗餘": ["茸於", "冗於"],
    "測試": ["策試", "側試"],
    "國家": ["果家"],
    "蘋果汁": ["蘋國汁"],
    "反應": ["反映"],
    "反映": ["反應"],
    "紀錄": ["記錄"],
    "記錄": ["紀錄"],
    "計畫": ["計劃"],
    "計劃": ["計畫"],
    "權利": ["權力", "全力"],
    "權力": ["權利", "全力"],
    "已經": ["以經"],
    "既然": ["即然"],
    "渡過": ["度過"],
    "度過": ["渡過"],
    "預訂": ["預定"],
    "簽訂": ["簽定"],
    "需要": ["須要"],
    "必須": ["必需"],
    "代表作": ["代表做"],
    "合作": ["合做"],
    "作為": ["做為"],
}


def encode_sentence_tensors(
    sentence: str,
    token_to_id: Dict[str, int],
    max_len: int = 48,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """
    Matches KyonLMScorer.score(sentences:) in WTFNeuralReranker.swift:
      tokens = [BOS] + chars[:max_len - 2] + [EOS]
      target_count = len(tokens) - 1
      input_ids[0:target_count]  = tokens[0:target_count]
      target_ids[0:target_count] = tokens[1:target_count+1]
      mask[0:target_count]       = 1.0
    """
    chars = list(sentence[: max_len - 2])
    tokens: List[int] = [BOS_ID]
    for ch in chars:
        tokens.append(token_to_id.get(ch, UNK_ID))
    tokens.append(EOS_ID)

    target_count = max(1, len(tokens) - 1)

    input_ids = torch.full((max_len,), PAD_ID, dtype=torch.long)
    target_ids = torch.full((max_len,), PAD_ID, dtype=torch.long)
    mask = torch.zeros((max_len,), dtype=torch.float32)

    for pos in range(target_count):
        input_ids[pos] = tokens[pos]
        target_ids[pos] = tokens[pos + 1]
        mask[pos] = 1.0

    return input_ids, target_ids, mask


class HomophoneSampler:
    """
    Indexes all same-reading words and single characters from Source/Data/data.txt
    and generates realistic same-reading homophone negative sentences.
    """

    def __init__(self, lexicon_path: str, max_word_len: int = 4) -> None:
        self.max_word_len = max_word_len
        self.reading_to_words: Dict[str, List[Tuple[str, float]]] = {}
        self.word_to_alternatives: Dict[str, List[str]] = {}
        self._build_index(lexicon_path)

    def _build_index(self, lexicon_path: str) -> None:
        word_readings: Dict[str, List[Tuple[str, float]]] = {}

        if os.path.exists(lexicon_path):
            with open(lexicon_path, "r", encoding="utf-8") as f:
                for raw_line in f:
                    parts = raw_line.strip().split()
                    if len(parts) < 3:
                        continue
                    reading, word, score_s = parts[0], parts[1], parts[2]
                    if reading.startswith("_"):
                        continue
                    if not (1 <= len(word) <= self.max_word_len):
                        continue
                    if not all("\u4e00" <= c <= "\u9fff" for c in word):
                        continue
                    try:
                        score = float(score_s)
                    except ValueError:
                        continue
                    # Keep reasonably plausible candidates so negative samples are hard negatives
                    if len(word) == 1 and score < -9.2:
                        continue
                    if len(word) >= 2 and score < -9.5:
                        continue

                    self.reading_to_words.setdefault(reading, []).append((word, score))
                    word_readings.setdefault(word, []).append((reading, score))

        for reading, items in self.reading_to_words.items():
            # Deduplicate words for the same reading, keeping best score
            dedup: Dict[str, float] = {}
            for w, sc in items:
                if w not in dedup or sc > dedup[w]:
                    dedup[w] = sc
            sorted_items = sorted(dedup.items(), key=lambda x: x[1], reverse=True)
            self.reading_to_words[reading] = sorted_items[:12]

        # Build fast lookup word -> list of same-reading alternative words
        for word, r_list in word_readings.items():
            alts: List[str] = []
            if word in PRIORITY_CONFUSABLES:
                for p_alt in PRIORITY_CONFUSABLES[word]:
                    if p_alt != word and p_alt not in alts:
                        alts.append(p_alt)

            for reading, _ in sorted(r_list, key=lambda x: x[1], reverse=True)[:2]:
                for cand_w, _ in self.reading_to_words.get(reading, []):
                    if cand_w != word and len(cand_w) == len(word) and cand_w not in alts:
                        alts.append(cand_w)
                        if len(alts) >= 8:
                            break
                # Also construct 2-char to two-1-char same-reading splits (like 測試 -> 策試)
                if len(word) == 2 and "-" in reading and len(alts) < 8:
                    syls = reading.split("-")
                    if len(syls) == 2:
                        c1_list = self.reading_to_words.get(syls[0], [])
                        c2_list = self.reading_to_words.get(syls[1], [])
                        if c1_list and c2_list:
                            for c1, _ in c1_list[:3]:
                                for c2, _ in c2_list[:3]:
                                    comp = c1 + c2
                                    if comp != word and len(comp) == 2 and comp not in alts:
                                        alts.append(comp)
                                        break
                                if len(alts) >= 8:
                                    break

            if alts:
                self.word_to_alternatives[word] = alts

        # Ensure all PRIORITY_CONFUSABLES keys are present even if not in data.txt
        for k, v_list in PRIORITY_CONFUSABLES.items():
            existing = self.word_to_alternatives.get(k, [])
            merged = list(v_list) + [x for x in existing if x not in v_list]
            self.word_to_alternatives[k] = merged

    def corrupt_sentence(
        self,
        sentence: str,
        rng: random.Random,
        max_replacements: int = 1,
    ) -> str:
        n = len(sentence)
        if n == 0:
            return sentence

        priority_spans: List[Tuple[int, int, List[str]]] = []
        general_spans: List[Tuple[int, int, List[str]]] = []

        # Scan for candidate spans (length 3 down to 1)
        for start in range(n):
            for span_len in (3, 2, 1):
                end = start + span_len
                if end > n:
                    continue
                sub = sentence[start:end]
                if sub in PRIORITY_CONFUSABLES:
                    priority_spans.append((start, end, PRIORITY_CONFUSABLES[sub]))
                elif sub in self.word_to_alternatives:
                    general_spans.append((start, end, self.word_to_alternatives[sub]))

        if not priority_spans and not general_spans:
            return sentence

        # Prefer priority confusables 70% of the time when available
        chosen_spans: List[Tuple[int, int, str]] = []
        pool = (
            priority_spans + general_spans
            if (priority_spans and rng.random() < 0.75)
            else (general_spans + priority_spans)
        )
        rng.shuffle(pool)

        occupied = [False] * n
        for start, end, alts in pool:
            if any(occupied[pos] for pos in range(start, end)):
                continue
            # Sample from top alternatives with preference for higher-ranked confusables
            top_k = alts[: min(len(alts), 5)]
            replacement = top_k[0] if (len(top_k) == 1 or rng.random() < 0.55) else rng.choice(top_k)
            if replacement != sentence[start:end]:
                chosen_spans.append((start, end, replacement))
                for pos in range(start, end):
                    occupied[pos] = True
                if len(chosen_spans) >= max_replacements:
                    break

        if not chosen_spans:
            return sentence

        chosen_spans.sort(key=lambda x: x[0])
        out_parts: List[str] = []
        cursor = 0
        for start, end, rep in chosen_spans:
            out_parts.append(sentence[cursor:start])
            out_parts.append(rep)
            cursor = end
        out_parts.append(sentence[cursor:])
        corrupted = "".join(out_parts)
        return corrupted


class KyonContrastiveDataset(Dataset):
    """
    PyTorch Dataset yielding (pos_in, pos_tgt, pos_mask, neg_in, neg_tgt, neg_mask).
    Uses dynamic on-the-fly homophone corruption so every epoch explores new
    hard negative combinations.
    """

    def __init__(
        self,
        sentences_path: str,
        token_to_id: Dict[str, int],
        sampler: HomophoneSampler,
        max_len: int = 48,
        is_train: bool = True,
        seed: int = 42,
    ) -> None:
        super().__init__()
        self.token_to_id = token_to_id
        self.sampler = sampler
        self.max_len = max_len
        self.is_train = is_train
        self.rng = random.Random(seed)

        self.sentences: List[str] = []
        if os.path.exists(sentences_path):
            with open(sentences_path, "r", encoding="utf-8") as f:
                for line in f:
                    s = line.strip()
                    if 4 <= len(s) <= max_len - 2:
                        self.sentences.append(s)

    def __len__(self) -> int:
        return len(self.sentences)

    def __getitem__(
        self, idx: int
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        pos_s = self.sentences[idx]

        # During training, with 20% probability, use a natural prefix (length >= 5)
        # so the model scores partial composing buffers accurately during typing.
        if self.is_train and len(pos_s) >= 8 and self.rng.random() < 0.20:
            cut = self.rng.randint(5, len(pos_s) - 1)
            pos_s = pos_s[:cut]

        max_rep = 2 if (self.is_train and len(pos_s) >= 10 and self.rng.random() < 0.25) else 1
        neg_s = self.sampler.corrupt_sentence(pos_s, self.rng, max_replacements=max_rep)

        # Fallback if no homophone found in sentence
        if neg_s == pos_s and len(pos_s) >= 2:
            alt_idx = (idx + 1) % len(self.sentences)
            neg_s = self.sampler.corrupt_sentence(self.sentences[alt_idx], self.rng, max_replacements=1)

        pos_in, pos_tgt, pos_mask = encode_sentence_tensors(pos_s, self.token_to_id, self.max_len)
        neg_in, neg_tgt, neg_mask = encode_sentence_tensors(neg_s, self.token_to_id, self.max_len)
        return pos_in, pos_tgt, pos_mask, neg_in, neg_tgt, neg_mask
