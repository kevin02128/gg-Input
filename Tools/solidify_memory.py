#!/usr/bin/env python3
"""
Memory Solidification Pipeline (Tools/solidify_memory.py)

Extracts high-frequency user override corrections from local JSON disk storage
(~/Library/Application Support/gg/user_overrides.json) and solidifies them into
the master colloquial dictionary (Source/Data/colloquial.txt) for permanent inclusion
in official .pkg releases.

Safeguards:
1. Enforces min-count threshold (default: >= 3) to prevent one-off typing mistakes from entering master dictionary.
2. Multi-syllable phrases (>= 2 syllables) are admitted directly.
3. Single characters must have a valid priorWord context to prevent poisoning global unigrams.
"""

import argparse
import json
import os
import sys
from pathlib import Path


def parse_arguments():
    repo_root = Path(__file__).resolve().parent.parent
    default_input = Path.home() / "Library" / "Application Support" / "gg" / "user_overrides.json"
    default_output = repo_root / "Source" / "Data" / "colloquial.txt"

    parser = argparse.ArgumentParser(description="Solidify user override memory into colloquial master dictionary.")
    parser.add_argument("--input", type=Path, default=default_input, help="Path to user_overrides.json")
    parser.add_argument("--output", type=Path, default=default_output, help="Path to colloquial.txt")
    parser.add_argument("--min-count", type=int, default=3, help="Minimum count threshold for solidification (default: 3)")
    parser.add_argument("--dry-run", action="store_true", help="Inspect candidates without writing to disk")
    return parser.parse_args()


def load_user_overrides(input_path: Path):
    if not input_path.exists():
        print(f"[solidify_memory] Warning: Input file not found: {input_path}")
        return []

    try:
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                return data
            elif isinstance(data, dict):
                return data.get("records", [])
    except Exception as e:
        print(f"[solidify_memory] Error reading {input_path}: {e}", file=sys.stderr)
        return []
    return []


def load_existing_colloquial(output_path: Path):
    existing_pairs = set()
    lines = []
    if output_path.exists():
        with open(output_path, "r", encoding="utf-8") as f:
            for line in f:
                lines.append(line)
                trimmed = line.strip()
                if not trimmed or trimmed.startswith("#"):
                    continue
                parts = trimmed.split()
                if len(parts) >= 2:
                    existing_pairs.add((parts[0], parts[1]))
    return lines, existing_pairs


def main():
    args = parse_arguments()
    print(f"[solidify_memory] Starting memory solidification...")
    print(f"  Input: {args.input}")
    print(f"  Output: {args.output}")
    print(f"  Min count threshold: {args.min_count}")
    print(f"  Dry run mode: {args.dry_run}")

    records = load_user_overrides(args.input)
    print(f"[solidify_memory] Total records loaded from user overrides: {len(records)}")

    existing_lines, existing_pairs = load_existing_colloquial(args.output)
    print(f"[solidify_memory] Existing entries in colloquial dictionary: {len(existing_pairs)}")

    candidates = []
    skipped_count = 0
    skipped_single_char = 0

    for rec in records:
        count = rec.get("count", 0)
        reading = rec.get("reading", "").strip()
        value = rec.get("value", "").strip()
        prior_word = rec.get("priorWord", "").strip()

        if count < args.min_count:
            skipped_count += 1
            continue

        if not reading or not value:
            continue

        # Check syllable count
        syllables = reading.split("-")
        if len(syllables) >= 2:
            candidates.append((reading, value, count, None))
        else:
            # Single character requires a compound context
            if prior_word and prior_word != "_START_":
                # We record with priorWord context indication
                candidates.append((reading, value, count, prior_word))
            else:
                skipped_single_char += 1

    print(f"[solidify_memory] Skipped {skipped_count} records below count threshold (< {args.min_count}).")
    print(f"[solidify_memory] Skipped {skipped_single_char} isolated single-character records without priorWord.")
    print(f"[solidify_memory] Total qualified candidates: {len(candidates)}")

    new_entries = []
    for reading, value, count, prior in candidates:
        if prior:
            # Single character with prior context
            # Currently preserved for compound expansion if readings are available
            print(f"  [Contextual] {prior} + {value} ({reading}) [count={count}]")
            continue

        pair = (reading, value)
        if pair not in existing_pairs:
            # Calculate score boost: base -3.0 with frequency bonus
            boosted_score = -3.0
            new_entries.append((reading, value, boosted_score, count))
            existing_pairs.add(pair)
            print(f"  [New] {reading} {value} {boosted_score:.2f} (user count: {count})")
        else:
            print(f"  [Exists] {reading} {value} (user count: {count})")

    if not new_entries:
        print("[solidify_memory] No new entries to append. Colloquial dictionary is up-to-date.")
        return

    if args.dry_run:
        print(f"[solidify_memory] Dry run complete. {len(new_entries)} entries would be added.")
        return

    # Append new entries to colloquial.txt
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "a", encoding="utf-8") as f:
        f.write(f"\n# Solidified from user overrides on {os.popen('date +%Y-%m-%d').read().strip()}\n")
        for reading, value, score, count in new_entries:
            f.write(f"{reading} {value} {score:.4f}\n")

    print(f"[solidify_memory] Successfully solidified {len(new_entries)} new entries into {args.output}.")


if __name__ == "__main__":
    main()
