#!/usr/bin/env python3
"""Build a compact, text-free character association table from licensed corpora.

The input corpora are not copied into the output. Only aggregated adjacent-Han
character counts are converted to association or conditional probability scores
and written to the table. Supports JSONL, TXT, and Parquet inputs.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import tempfile
from collections import Counter
from pathlib import Path

try:
    import opencc
    CONVERTER = opencc.OpenCC("s2twp")
except ImportError:
    CONVERTER = None

try:
    import pyarrow.parquet as parquet
except ImportError:
    parquet = None


HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")


def is_han(char: str) -> bool:
    return bool(HAN_RE.fullmatch(char))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", action="append", required=True, help="Corpus input (.jsonl, .txt, or .parquet); may be supplied more than once")
    parser.add_argument("--output", required=True, help="Output TSV path")
    parser.add_argument("--column", action="append", help="Text column for parquet/jsonl inputs; defaults to text, then ch, then first column")
    parser.add_argument("--source-description", help="Short attribution written to the output header")
    parser.add_argument("--ngram-order", choices=("both", "bigram", "trigram"), default="both")
    parser.add_argument("--metric", choices=("pmi", "cond_prob"), default="pmi", help="Score metric: pmi (positive PMI in ln units) or cond_prob (log10 conditional probability)")
    parser.add_argument("--min-pair-count", type=int, default=3)
    parser.add_argument("--min-trigram-count", type=int, default=3)
    parser.add_argument("--min-bigram-score", type=float, default=0.25)
    parser.add_argument("--min-trigram-score", type=float, default=3.0)
    args = parser.parse_args()

    if args.min_pair_count < 1 or args.min_trigram_count < 1:
        parser.error("minimum pair and trigram counts must be positive")

    column_overrides = args.column or []
    if len(column_overrides) not in (0, len(args.input)):
        parser.error("provide either no --column options or one --column per --input")

    with tempfile.TemporaryDirectory(prefix="gg-character-ngrams-") as temp_dir:
        db = sqlite3.connect(Path(temp_dir) / "deduplicated-sentences.sqlite3")
        db.execute("CREATE TABLE sentences (text TEXT PRIMARY KEY) WITHOUT ROWID")
        source_rows = 0
        accepted_rows = 0

        for input_index, input_path_str in enumerate(args.input):
            input_path = Path(input_path_str)
            requested_column = column_overrides[input_index] if column_overrides else "text"

            if input_path.suffix == ".parquet":
                if parquet is None:
                    parser.error("pyarrow is required to read Parquet files. Convert to .jsonl or install pyarrow.")
                parquet_file = parquet.ParquetFile(input_path_str)
                actual_column = requested_column if requested_column in parquet_file.schema.names else next((name for name in ("text", "ch") if name in parquet_file.schema.names), parquet_file.schema.names[0])
                for batch in parquet_file.iter_batches(columns=[actual_column], batch_size=16_384):
                    for raw_text in batch.column(0).to_pylist():
                        source_rows += 1
                        if raw_text is None:
                            continue
                        text = str(raw_text).strip()
                        if CONVERTER is not None:
                            text = CONVERTER.convert(text)
                        han_count = sum(1 for char in text if is_han(char))
                        if not (8 <= len(text) <= 120 and han_count >= 6):
                            continue
                        cursor = db.execute("INSERT OR IGNORE INTO sentences(text) VALUES (?)", (text,))
                        accepted_rows += cursor.rowcount
                    if source_rows % 250_000 < 16_384:
                        db.commit()
                        print(f"Processed {source_rows:,} source rows; {accepted_rows:,} unique eligible sentences", flush=True)

            elif input_path.suffix == ".jsonl":
                with input_path.open("r", encoding="utf-8") as f:
                    for line in f:
                        source_rows += 1
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            record = json.loads(line)
                            raw_text = record.get(requested_column) or record.get("text") or record.get("ch") or next(iter(record.values()))
                        except Exception:
                            raw_text = line
                        if not raw_text:
                            continue
                        text = str(raw_text).strip()
                        if CONVERTER is not None:
                            text = CONVERTER.convert(text)
                        han_count = sum(1 for char in text if is_han(char))
                        if not (8 <= len(text) <= 120 and han_count >= 6):
                            continue
                        cursor = db.execute("INSERT OR IGNORE INTO sentences(text) VALUES (?)", (text,))
                        accepted_rows += cursor.rowcount
                        if source_rows % 250_000 == 0:
                            db.commit()
                            print(f"Processed {source_rows:,} source rows; {accepted_rows:,} unique eligible sentences", flush=True)

            else: # Plain text lines
                with input_path.open("r", encoding="utf-8") as f:
                    for line in f:
                        source_rows += 1
                        text = line.strip()
                        if not text:
                            continue
                        if CONVERTER is not None:
                            text = CONVERTER.convert(text)
                        han_count = sum(1 for char in text if is_han(char))
                        if not (8 <= len(text) <= 120 and han_count >= 6):
                            continue
                        cursor = db.execute("INSERT OR IGNORE INTO sentences(text) VALUES (?)", (text,))
                        accepted_rows += cursor.rowcount
                        if source_rows % 250_000 == 0:
                            db.commit()
                            print(f"Processed {source_rows:,} source rows; {accepted_rows:,} unique eligible sentences", flush=True)

        db.commit()
        print(f"Finished deduplication. Total source rows: {source_rows:,}; Unique eligible sentences: {accepted_rows:,}", flush=True)

        character_counts: Counter[str] = Counter()
        pair_counts: Counter[tuple[str, str]] = Counter()
        trigram_counts: Counter[tuple[str, str, str]] = Counter()
        sentence_count = 0
        total_pairs = 0
        for (text,) in db.execute("SELECT text FROM sentences"):
            sentence_count += 1
            previous = None
            before_previous = None
            for char in text:
                if not is_han(char):
                    previous = None
                    before_previous = None
                    continue
                character_counts[char] += 1
                if previous is not None:
                    pair_counts[(previous, char)] += 1
                    total_pairs += 1
                    if before_previous is not None and args.ngram_order != "bigram":
                        trigram_counts[(before_previous, previous, char)] += 1
                    before_previous = previous
                previous = char

    if total_pairs == 0:
        raise SystemExit("No adjacent Han-character pairs found")

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    source_description = args.source_description or ", ".join(Path(path).name for path in args.input)
    source_description = source_description.replace("\n", " ").replace("\r", " ")
    emitted = 0
    with output_path.open("w", encoding="utf-8", newline="\n") as output:
        if args.metric == "pmi":
            output.write("# gg character n-gram association table; positive PMI in natural-log units\n")
            output.write(
                f"# ngram_order={args.ngram_order}; unique_eligible_sentences={sentence_count}; "
                f"min_pair_count={args.min_pair_count}; min_trigram_count={args.min_trigram_count}; "
                f"min_bigram_score={args.min_bigram_score}; min_trigram_score={args.min_trigram_score}; clip=4.0\n"
            )
        else:
            output.write("# gg character n-gram conditional log-probability table (log10 units)\n")
            output.write(
                f"# ngram_order={args.ngram_order}; unique_eligible_sentences={sentence_count}; "
                f"min_pair_count={args.min_pair_count}; min_trigram_count={args.min_trigram_count}\n"
            )

        output.write(f"# sources: {source_description}; see NOTICE for attribution\n")
        output.write("# fields: B previous_scalar_hex next_scalar_hex score, or T first_scalar_hex second_scalar_hex next_scalar_hex score\n")

        if args.ngram_order != "trigram":
            for (previous, next_char), count in sorted(pair_counts.items()):
                if count < args.min_pair_count:
                    continue
                if args.metric == "pmi":
                    pmi = math.log((count * total_pairs) / (character_counts[previous] * character_counts[next_char]))
                    score = min(4.0, max(0.0, pmi))
                    if score < args.min_bigram_score:
                        continue
                else: # cond_prob log10 P(next | previous)
                    score = math.log10(count / character_counts[previous])
                output.write(f"B {ord(previous):04X} {ord(next_char):04X} {score:.6f}\n")
                emitted += 1

        if args.ngram_order != "bigram":
            for (first, second, next_char), count in sorted(trigram_counts.items()):
                if count < args.min_trigram_count:
                    continue
                if args.metric == "pmi":
                    prefix_count = pair_counts[(first, second)]
                    continuation_count = pair_counts[(second, next_char)]
                    association = math.log((count * character_counts[second]) / (prefix_count * continuation_count))
                    score = min(4.0, max(0.0, association))
                    if score < args.min_trigram_score:
                        continue
                else: # cond_prob log10 P(next | first, second)
                    prefix_count = pair_counts[(first, second)]
                    if prefix_count <= 0:
                        continue
                    score = math.log10(count / prefix_count)
                output.write(f"T {ord(first):04X} {ord(second):04X} {ord(next_char):04X} {score:.6f}\n")
                emitted += 1

    print(f"Wrote {emitted:,} aggregated n-grams to {output_path} from {sentence_count:,} unique sentences")


if __name__ == "__main__":
    main()
