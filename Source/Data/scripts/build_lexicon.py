#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_lexicon.py

Single unified lexicon builder for gg (McBopomofo).
Consolidates modernize_lexicon.py and merge_modern_lexicon.py:
- Reads Source/Data/modern_vocabulary.tsv and optional external TSV/TXT files.
- Validates Bopomofo readings (rejects ASCII letters, spaces, or prefix light tones '˙').
- Clamps log10 probabilities to [-8.50000000, -1.50000000] and formats to .8f.
- Demotes archaic homophones that previously caused weight inversions (e.g. 忿, 眈).
- Sorts keys strictly by UTF-8 byte order (LC_ALL=C) for C++ ParselessPhraseDB binary search.
- Updates associated-phrases-v2.txt.
"""

import argparse
import math
import re
import subprocess
import sys
from pathlib import Path

HEADER_LINE = "# format org.openvanilla.mcbopomofo.sorted\n"
MIN_LOG_PROB = -8.50000000
MAX_LOG_PROB = -1.50000000

# Valid single Bopomofo syllable pattern: Bopomofo chars [\u3105-\u312f] followed by optional tone [ˊˇˋ˙]
BPMF_SYLLABLE_RE = re.compile(r"^[\u3105-\u312f]+[ˊˇˋ˙]?$")

# Explicit demotions for archaic single-character homophones
ARCHAIC_DEMOTIONS = [
    ("ㄈㄣˋ", "忿", -6.50000000),
    ("ㄉㄢ", "眈", -6.80000000),
]


def clamp_prob(val: float) -> float:
    return max(MIN_LOG_PROB, min(MAX_LOG_PROB, val))


def is_valid_bopomofo_reading(reading: str) -> bool:
    """Validates that a hyphen-separated reading contains only valid Bopomofo syllables
    with tone marks (including light tone '˙') strictly at the end of each syllable.
    """
    if not reading or " " in reading:
        return False
    syllables = reading.split("-")
    for syl in syllables:
        if not syl or syl.startswith("˙"):
            return False
        if not BPMF_SYLLABLE_RE.match(syl):
            return False
    return True


def normalize_reading(reading: str) -> str:
    """Normalizes numeric tones and moves any accidental leading '˙' on a syllable to the end."""
    reading = reading.strip().replace(" ", "-").replace("/", "-")
    reading = (
        reading.replace("5", "˙")
        .replace("1", "")
        .replace("2", "ˊ")
        .replace("3", "ˇ")
        .replace("4", "ˋ")
    )
    syllables = []
    for syl in reading.split("-"):
        if syl.startswith("˙") and len(syl) > 1:
            syl = syl[1:] + "˙"
        syllables.append(syl)
    return "-".join(syllables)


def load_existing_data_txt(filepath: Path) -> dict:
    key_to_entries = {}
    total_lines = 0

    with open(filepath, "r", encoding="utf-8") as f:
        header = f.readline()
        if not header.startswith("# format org.openvanilla.mcbopomofo.sorted"):
            print(f"[Warning] Unexpected header: {header.strip()}")

        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split(" ")
            if len(parts) >= 3:
                key, val = parts[0], parts[1]
                try:
                    score = float(parts[2])
                except ValueError:
                    continue
                key_to_entries.setdefault(key, []).append([val, score])
                total_lines += 1

    print(f"[Lexicon] Loaded {total_lines:,} entries across {len(key_to_entries):,} keys from {filepath.name}.")
    return key_to_entries


def load_tsv_vocabulary(tsv_path: Path) -> list:
    vocab = []
    rejected = 0
    with open(tsv_path, "r", encoding="utf-8") as f:
        for line_num, raw_line in enumerate(f, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 3:
                continue
            raw_reading, word, raw_score = parts[0], parts[1], parts[2]
            reading = normalize_reading(raw_reading)
            if not is_valid_bopomofo_reading(reading):
                print(f"[Warning] Skipping invalid Bopomofo reading at {tsv_path.name}:{line_num}: {raw_reading} ({word})")
                rejected += 1
                continue
            try:
                score = float(raw_score)
            except ValueError:
                continue
            vocab.append((reading, word, score))
    if rejected > 0:
        print(f"[Lexicon] Rejected {rejected} invalid entries from {tsv_path.name}.")
    return vocab


def merge_vocabulary_list(key_to_entries: dict, vocab_list: list, allow_demote: bool = False):
    added = 0
    updated = 0

    for reading, word, raw_score in vocab_list:
        score = clamp_prob(float(raw_score))
        if reading not in key_to_entries:
            key_to_entries[reading] = [[word, score]]
            added += 1
        else:
            existing_idx = -1
            for idx, (ex_word, _) in enumerate(key_to_entries[reading]):
                if ex_word == word:
                    existing_idx = idx
                    break
            if existing_idx >= 0:
                old_score = key_to_entries[reading][existing_idx][1]
                if allow_demote or score > old_score:
                    key_to_entries[reading][existing_idx][1] = score
                    updated += 1
            else:
                key_to_entries[reading].append([word, score])
                added += 1

    print(f"[Lexicon] Added {added:,} new entries, updated {updated:,} existing entries.")


def merge_external_file(key_to_entries: dict, external_file: Path, total_corpus_freq: float = None):
    if not external_file.exists():
        print(f"[Error] External lexicon file not found: {external_file}")
        sys.exit(1)

    raw_items = []
    calculated_total = 0.0

    with open(external_file, "r", encoding="utf-8") as f:
        for line_num, raw_line in enumerate(f, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 3:
                continue
            p0, p1, p2 = parts[0], parts[1], parts[2]
            try:
                num_val = float(p2)
            except ValueError:
                continue

            if any("\u3105" <= c <= "\u312f" or c in "ˊˇˋ˙-" for c in p0):
                reading, word = p0, p1
            else:
                word, reading = p0, p1

            reading = normalize_reading(reading)
            if not is_valid_bopomofo_reading(reading):
                continue

            raw_items.append((reading, word, num_val))
            if num_val > 0:
                calculated_total += num_val

    denom = total_corpus_freq if total_corpus_freq else (calculated_total if calculated_total > 0 else 1e7)
    normalized_list = []
    for reading, word, val in raw_items:
        log_prob = clamp_prob(val if val <= 0 else math.log10(val / denom))
        normalized_list.append((reading, word, log_prob))

    merge_vocabulary_list(key_to_entries, normalized_list)


def write_sorted_data_txt(key_to_entries: dict, output_path: Path):
    sorted_keys = sorted(key_to_entries.keys(), key=lambda k: k.encode("utf-8"))
    temp_path = output_path.with_suffix(".tmp")
    total_written = 0

    with open(temp_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER_LINE)
        for key in sorted_keys:
            candidates = sorted(key_to_entries[key], key=lambda item: item[1], reverse=True)
            for word, score in candidates:
                f.write(f"{key} {word} {score:.8f}\n")
                total_written += 1

    temp_path.replace(output_path)
    print(f"[Lexicon] Wrote {total_written:,} sorted lines to {output_path.name}.")
    verify_sorting(output_path)


def verify_sorting(filepath: Path):
    prev_key_bytes = b""
    line_num = 1
    with open(filepath, "r", encoding="utf-8") as f:
        header = f.readline()
        if header != HEADER_LINE:
            raise ValueError(f"Invalid header in {filepath}: {header!r}")
        for line in f:
            line_num += 1
            parts = line.split(" ")
            if not parts:
                continue
            key_bytes = parts[0].encode("utf-8")
            if key_bytes < prev_key_bytes:
                raise ValueError(f"Byte-sorting violation at line {line_num}: {prev_key_bytes} > {key_bytes}")
            prev_key_bytes = key_bytes
    print(f"[Lexicon] Verified strict UTF-8 byte sorting on {line_num:,} lines.")


def update_associated_phrases(project_root: Path):
    data_txt = project_root / "Source" / "Data" / "data.txt"
    assoc_target = project_root / "Source" / "Data" / "associated-phrases-v2.txt"
    assoc_punct = project_root / "Source" / "Data" / "associated-punctuation.txt"

    if not (data_txt.exists() and assoc_punct.exists()):
        return

    cmd = [
        sys.executable,
        "-m",
        "curation.builders.phrase_deriver",
        str(data_txt),
        str(assoc_target),
        str(assoc_punct),
    ]
    res = subprocess.run(cmd, cwd=str(project_root / "Source" / "Data"), capture_output=True, text=True)
    if res.returncode == 0:
        print(f"[Lexicon] Updated {assoc_target.name} via phrase_deriver.")
    else:
        print(f"[Warning] phrase_deriver returned non-zero: {res.stderr.strip()}")


def main():
    parser = argparse.ArgumentParser(description="Build and sort McBopomofo data.txt with modern Taiwanese vocabulary.")
    parser.add_argument("--data", default="Source/Data/data.txt", help="Path to data.txt")
    parser.add_argument("--vocab", default="Source/Data/modern_vocabulary.tsv", help="Path to modern_vocabulary.tsv")
    parser.add_argument("--external", default=None, help="Optional external lexicon TSV/TXT file")
    parser.add_argument("--skip-assoc", action="store_true", help="Skip updating associated-phrases-v2.txt")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent.parent.parent
    data_path = Path(args.data) if Path(args.data).is_absolute() else (project_root / args.data)
    vocab_path = Path(args.vocab) if Path(args.vocab).is_absolute() else (project_root / args.vocab)

    if not data_path.exists():
        print(f"[Error] data.txt not found at {data_path}")
        sys.exit(1)

    entries = load_existing_data_txt(data_path)

    if vocab_path.exists():
        vocab_list = load_tsv_vocabulary(vocab_path)
        merge_vocabulary_list(entries, vocab_list, allow_demote=False)

    merge_vocabulary_list(entries, ARCHAIC_DEMOTIONS, allow_demote=True)

    if args.external:
        ext_path = Path(args.external) if Path(args.external).is_absolute() else (project_root / args.external)
        merge_external_file(entries, ext_path)

    write_sorted_data_txt(entries, data_path)

    if not args.skip_assoc:
        update_associated_phrases(project_root)


if __name__ == "__main__":
    main()
