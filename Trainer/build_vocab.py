#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KyonLM Vocabulary Builder (build_vocab.py)

Builds a character-level vocabulary (vocab.txt) for KyonLM from the gg lexicon
(Source/Data/data.txt).

Format of vocab.txt:
  Line 0: [PAD]
  Line 1: [UNK]
  Line 2: [BOS]
  Line 3: [EOS]
  Line 4..N: Single character per line (Traditional Chinese characters sorted by
             unigram/phrase frequency, Bopomofo symbols, full-width punctuation,
             and printable ASCII).
"""

import argparse
import hashlib
import os
from typing import Dict, List, Tuple

SPECIAL_TOKENS = ["[PAD]", "[UNK]", "[BOS]", "[EOS]"]

BOPOMOFO_CHARS = (
    "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
    "ㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
    "ˊˇˋ˙"
)

FULLWIDTH_PUNCTUATION = (
    "，。！？；：「」『』（）—…、．《》〈〉【】〔〕"
    "＋－＊／＝％＆＃＠～｜＼"
)

ASCII_CHARS = (
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    ".,!?;:'\"()-_/+*=<>[]{}@#$%^&~`|"
)


def compute_file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def build_vocab(
    lexicon_path: str,
    output_path: str,
    max_vocab_size: int = 10500,
) -> Tuple[List[str], str]:
    char_best_score: Dict[str, float] = {}
    char_occurrence: Dict[str, int] = {}

    if os.path.exists(lexicon_path):
        with open(lexicon_path, "r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) < 3:
                    continue
                reading, word, score_str = parts[0], parts[1], parts[2]
                if reading.startswith("_"):
                    continue
                try:
                    score = float(score_str)
                except ValueError:
                    score = -10.0

                for ch in word:
                    if len(ch) != 1 or ch.isspace():
                        continue
                    char_occurrence[ch] = char_occurrence.get(ch, 0) + 1
                    # Prefer explicit single-char unigram score; otherwise discount phrase score slightly
                    effective_score = score if len(word) == 1 else (score - 1.5)
                    prev = char_best_score.get(ch, -999.0)
                    if effective_score > prev:
                        char_best_score[ch] = effective_score

    # Guarantee priority inclusion of Bopomofo, full-width punctuation, and ASCII
    mandatory_chars: List[str] = []
    seen = set(SPECIAL_TOKENS)

    for group in (BOPOMOFO_CHARS, FULLWIDTH_PUNCTUATION, ASCII_CHARS):
        for ch in group:
            if len(ch) == 1 and not ch.isspace() and ch not in seen:
                seen.add(ch)
                mandatory_chars.append(ch)

    # Sort lexicon characters by (best_score + 0.15 * log1p(occurrence)) descending
    import math
    ranked_lex_chars = sorted(
        (ch for ch in char_best_score.keys() if ch not in seen),
        key=lambda c: (
            char_best_score[c] + 0.15 * math.log1p(char_occurrence.get(c, 1)),
            -ord(c),
        ),
        reverse=True,
    )

    budget_for_lex = max(0, max_vocab_size - len(SPECIAL_TOKENS) - len(mandatory_chars))
    selected_lex_chars = ranked_lex_chars[:budget_for_lex]

    vocab_list = SPECIAL_TOKENS + mandatory_chars + selected_lex_chars

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        for token in vocab_list:
            f.write(f"{token}\n")

    sha256_hex = compute_file_sha256(output_path)
    return vocab_list, sha256_hex


def load_vocab(vocab_path: str) -> Tuple[Dict[str, int], Dict[int, str], str]:
    token_to_id: Dict[str, int] = {}
    id_to_token: Dict[int, str] = {}
    with open(vocab_path, "r", encoding="utf-8") as f:
        for idx, raw_line in enumerate(f):
            token = raw_line.rstrip("\r\n")
            if not token:
                continue
            token_to_id[token] = idx
            id_to_token[idx] = token
    sha256_hex = compute_file_sha256(vocab_path)
    return token_to_id, id_to_token, sha256_hex


def main() -> None:
    parser = argparse.ArgumentParser(description="Build KyonLM vocab.txt from gg data.txt")
    parser.add_argument(
        "--lexicon",
        type=str,
        default="./Source/Data/data.txt",
        help="Path to gg data.txt",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="../gg_trainer/data/vocab.txt",
        help="Output vocab.txt path",
    )
    parser.add_argument(
        "--max-vocab",
        type=int,
        default=10500,
        help="Maximum vocabulary size (default: 10500)",
    )
    args = parser.parse_args()

    vocab_list, sha256_hex = build_vocab(
        lexicon_path=args.lexicon,
        output_path=args.output,
        max_vocab_size=args.max_vocab,
    )
    print(f"[build_vocab] Saved {len(vocab_list)} tokens to {args.output}")
    print(f"[build_vocab] Header tokens: {vocab_list[:4]}")
    print(f"[build_vocab] kyon.vocab_sha256 = {sha256_hex}")


if __name__ == "__main__":
    main()
